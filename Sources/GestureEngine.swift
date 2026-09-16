import Cocoa
import QuartzCore

/// Owns the CGEvent tap and the per-button state machine:
/// click / double click / hold actions, click-and-drag effects, click-and-scroll effects,
/// plus routing of plain scroll-wheel events to the ScrollEngine.
final class GestureEngine {
    private(set) var isRunning = false
    private(set) var lastError: String?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var config: Config { SettingsStore.shared.config }

    let scrollEngine = ScrollEngine()
    private let zoomStream = GestureStream(kind: .magnify)
    private let rotateStream = GestureStream(kind: .rotate)
    private var hold: Hold?
    private var momentum: Momentum?
    private var lastClick: (button: Int, time: CFTimeInterval, count: Int)?
    private var pendingClick: (timer: DispatchWorkItem, run: () -> Void)?
    private var appSwitcherOpen = false
    private var lastSpaceStep: CFTimeInterval = 0

    enum Axis { case undecided, horizontal, vertical }
    enum ScrollPhase: Int64 { case began = 1, changed = 2, ended = 4 }
    enum MomentumPhase: Int64 { case none = 0, begin = 1, `continue` = 2, end = 3 }

    final class Hold {
        let button: Int
        let cfg: ButtonConfig
        let start: CGPoint
        let clickCount: Int
        var accX = 0.0, accY = 0.0
        var dragStarted = false
        var axis: Axis = .undecided
        var holdFired = false
        var usedAsScrollModifier = false
        var holdTimer: Timer?
        var pointerFrozen = false
        // Drag-to-scroll: input is smoothed like Mac Mouse Fix's 3/60 s linear animator, and the exit
        // velocity is the last delivered delta divided by the time since the previous input.
        var scrollPending = (x: 0.0, y: 0.0)      // px received but not yet emitted
        var scrollTimer: Timer?
        var lastInputTime: CFTimeInterval = 0
        var lastInputDelta = (x: 0.0, y: 0.0)
        var lastInputInterval = Double.greatestFiniteMagnitude
        var scrollCarry = (x: 0.0, y: 0.0)
        // Fallback (hotkey-based Spaces switching when dock swipes are unavailable)
        var spaceAcc = 0.0, spaceFires = 0, lastSpaceFire: CFTimeInterval = 0, verticalFired = false
        init(button: Int, cfg: ButtonConfig, start: CGPoint, clickCount: Int) {
            self.button = button; self.cfg = cfg; self.start = start; self.clickCount = clickCount
        }
    }

    final class Momentum {
        var vx: Double, vy: Double
        var remX = 0.0, remY = 0.0
        var timer: Timer?
        init(vx: Double, vy: Double) { self.vx = vx; self.vy = vy }
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .leftMouseDown, .rightMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let engine = Unmanaged<GestureEngine>.fromOpaque(refcon!).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lastError = "Could not create the event tap (Accessibility permission missing?)"
            Log.info(lastError!)
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        lastError = nil
        Log.info("event tap running (dock swipes: \(DockSwipe.shared.available), SkyLight hotkeys: \(SkyLight.available))")
    }

    func stop() {
        cancelHold()
        stopMomentum()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; isRunning = false
    }

    // MARK: Event tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.info("tap disabled (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            cancelHold() // a button-up may have been missed while the tap was off
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == HotKeyPoster.eventTag { return pass }
        // Always finish a hold we own, even if the app was disabled mid-press.
        if let h = hold, type == .otherMouseUp, Int(event.getIntegerValueField(.mouseEventButtonNumber)) == h.button {
            hold = nil
            h.holdTimer?.invalidate()
            release(h, at: event.location, runActions: config.enabled)
            return nil
        }
        guard config.enabled else { return pass }

        switch type {
        case .leftMouseDown, .rightMouseDown:
            stopMomentum()
            return pass

        case .scrollWheel:
            if let h = hold, h.cfg.scroll != .off, !h.dragStarted, event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
                h.usedAsScrollModifier = true
                h.holdTimer?.invalidate()
                modifiedScroll(h, event: event)
                return nil
            }
            stopMomentum()
            return scrollEngine.handle(event, forced: nil) ? nil : pass

        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            stopMomentum()
            if let h = hold {
                if h.button == button { cancelHold() } else { return pass }   // missed button-up: clean up and start over
            }
            let cfg = config.button(button)
            guard cfg.isCaptured else { return pass }
            let now = CACurrentMediaTime()
            var count = 1
            if let lc = lastClick, lc.button == button, now - lc.time < 0.35 { count = lc.count + 1 }
            lastClick = (button, now, count)
            let h = Hold(button: button, cfg: cfg, start: event.location, clickCount: count)
            hold = h
            if cfg.hold != .none {
                let t = Timer(timeInterval: 0.35, repeats: false) { [weak self, weak h] _ in
                    guard let self, let h, self.hold === h, !h.dragStarted, !h.usedAsScrollModifier else { return }
                    h.holdFired = true
                    self.firePendingClick()
                    ActionRunner.run(cfg.hold, shortcut: cfg.holdShortcut, button: button, at: h.start)
                }
                RunLoop.main.add(t, forMode: .common)
                h.holdTimer = t
            }
            Log.debug("hold start button=\(button) clickCount=\(count)")
            return nil

        case .otherMouseDragged:
            guard let h = hold, Int(event.getIntegerValueField(.mouseEventButtonNumber)) == h.button else { return pass }
            let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
            let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
            drag(h, dx: dx, dy: dy)
            return nil

        case .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard let h = hold, h.button == button else { return pass }
            hold = nil
            h.holdTimer?.invalidate()
            release(h, at: event.location)
            return nil

        default:
            return pass
        }
    }

    // MARK: Click and drag

    private func drag(_ h: Hold, dx: Double, dy: Double) {
        h.accX += dx; h.accY += dy
        guard h.cfg.drag != .off, !h.holdFired else { return }   // a hold action already consumed this press
        let natural = config.spacesNaturalDirection ? 1.0 : -1.0

        if !h.dragStarted {
            let startThreshold = h.cfg.drag == .spacesAndMissionControl ? 8.0 : 3.0
            guard hypot(h.accX, h.accY) >= startThreshold else { return }
            h.dragStarted = true
            h.holdTimer?.invalidate()
            firePendingClick() // a click that preceded this drag was a real click
            if config.freezePointerDuringDrag {
                CGAssociateMouseAndMouseCursorPosition(0)
                CGWarpMouseCursorPosition(h.start)
                h.pointerFrozen = true
            }
            switch h.cfg.drag {
            case .spacesAndMissionControl:
                h.axis = abs(h.accX) >= abs(h.accY) ? .horizontal : .vertical
                if DockSwipe.shared.available {
                    DockSwipe.shared.begin(kind: h.axis == .horizontal ? .horizontal : .vertical,
                                           at: h.start, scaleMultiplier: config.spacesDragScale)
                    DockSwipe.shared.update(dx: h.accX * natural, dy: h.accY)
                } else {
                    h.spaceAcc = h.accX
                }
                Log.debug("spaces drag axis=\(h.axis) dockswipe=\(DockSwipe.shared.available)")
            case .scrollAndNavigate:
                postScroll(dx: 0, dy: 0, phase: .began)
                let (sx, sy) = dragScrollDeltas(h.accX, h.accY)
                dragScrollInput(h, dx: sx, dy: sy)
                let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak h] _ in
                    guard let self, let h else { return }
                    self.dragScrollFrame(h)
                }
                RunLoop.main.add(t, forMode: .common)
                h.scrollTimer = t
            case .off: break
            }
            return
        }

        switch h.cfg.drag {
        case .spacesAndMissionControl:
            if DockSwipe.shared.isActive {
                DockSwipe.shared.update(dx: dx * natural, dy: dy)
            } else {
                legacySpacesDrag(h, dx: dx * natural)
            }
        case .scrollAndNavigate:
            let (sx, sy) = dragScrollDeltas(dx, dy)
            dragScrollInput(h, dx: sx, dy: sy)
        case .off: break
        }
    }

    private func dragScrollInput(_ h: Hold, dx: Double, dy: Double) {
        let now = CACurrentMediaTime()
        if h.lastInputTime != 0 { h.lastInputInterval = now - h.lastInputTime }
        h.lastInputTime = now
        h.lastInputDelta = (dx, dy)
        h.scrollPending.x += dx; h.scrollPending.y += dy
    }

    /// Emits the smoothed drag-to-scroll movement: one third of what is pending per frame
    /// (a 3-frame linear ramp, as in Mac Mouse Fix), so 1000 Hz input becomes 120 Hz output.
    private func dragScrollFrame(_ h: Hold) {
        guard h.scrollPending.x != 0 || h.scrollPending.y != 0 else { return }
        var ex = h.scrollPending.x / 3, ey = h.scrollPending.y / 3
        if abs(h.scrollPending.x) < 3 { ex = h.scrollPending.x }
        if abs(h.scrollPending.y) < 3 { ey = h.scrollPending.y }
        h.scrollPending.x -= ex; h.scrollPending.y -= ey
        let fx = ex + h.scrollCarry.x, fy = ey + h.scrollCarry.y
        let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
        h.scrollCarry = (fx - ix, fy - iy)
        if ix != 0 || iy != 0 { postScroll(dx: ix, dy: iy, phase: .changed) }
    }

    /// Hotkey-based Spaces switching, used only when real dock swipes are unavailable.
    private func legacySpacesDrag(_ h: Hold, dx: Double) {
        if h.axis == .horizontal {
            h.spaceAcc += dx
            let threshold = h.spaceFires == 0 ? 28.0 : 140.0
            if abs(h.spaceAcc) >= threshold {
                let now = CACurrentMediaTime()
                if now - h.lastSpaceFire > 0.3 {
                    HotKeyPoster.post(h.spaceAcc < 0 ? .moveRightASpace : .moveLeftASpace)
                    h.spaceFires += 1; h.lastSpaceFire = now
                }
                h.spaceAcc = 0
            }
        } else if !h.verticalFired, abs(h.accY) >= 28 {
            HotKeyPoster.post(h.accY < 0 ? .missionControl : .appExpose)
            h.verticalFired = true
        }
    }

    private func dragScrollDeltas(_ dx: Double, _ dy: Double) -> (Double, Double) {
        config.dragScrollInvert ? (-dx, -dy) : (dx, dy)
    }

    private func unfreeze(_ h: Hold) {
        if h.pointerFrozen { CGAssociateMouseAndMouseCursorPosition(1); h.pointerFrozen = false }
        h.scrollTimer?.invalidate(); h.scrollTimer = nil
    }

    // MARK: Release → click actions

    /// Forcibly ends the current hold without running click actions (tap lost, app disabled, restart).
    func cancelHold() {
        guard let h = hold else { return }
        hold = nil
        h.holdTimer?.invalidate()
        release(h, at: nil, runActions: false)
    }

    private func release(_ h: Hold, at location: CGPoint?, runActions: Bool = true) {
        unfreeze(h)
        Log.debug("release button=\(h.button) drag=\(h.dragStarted) hold=\(h.holdFired) scrollMod=\(h.usedAsScrollModifier)")

        if h.usedAsScrollModifier || h.dragStarted || h.holdFired { lastClick = nil } // not part of a double click
        if h.usedAsScrollModifier {
            zoomStream.finish(); rotateStream.finish()
            if appSwitcherOpen { HotKeyPoster.postKeyEvent(55, down: false, flags: 0); appSwitcherOpen = false }
            scrollEngine.flush()
            return
        }
        if h.dragStarted {
            switch h.cfg.drag {
            case .spacesAndMissionControl: DockSwipe.shared.end()
            case .scrollAndNavigate:
                h.scrollTimer?.invalidate()
                // flush whatever the smoothing ramp still holds
                let rx = h.scrollPending.x + h.scrollCarry.x, ry = h.scrollPending.y + h.scrollCarry.y
                if rx.rounded() != 0 || ry.rounded() != 0 { postScroll(dx: rx.rounded(), dy: ry.rounded(), phase: .changed) }
                postScroll(dx: 0, dy: 0, phase: .ended)
                if config.dragScrollMomentum {
                    let since = CACurrentMediaTime() - h.lastInputTime
                    // No momentum when the pointer had already stopped before the button came up.
                    if since <= 0.1, h.lastInputInterval > 0, h.lastInputInterval < 0.1 {
                        startMomentum(vx: h.lastInputDelta.x / h.lastInputInterval, vy: h.lastInputDelta.y / h.lastInputInterval)
                    }
                }
            case .off: break
            }
            return
        }
        if h.holdFired || !runActions { return }

        let cfg = h.cfg
        let loc = location ?? h.start
        if h.clickCount >= 2, cfg.doubleClick != .none {
            pendingClick?.timer.cancel(); pendingClick = nil
            lastClick = nil
            ActionRunner.run(cfg.doubleClick, shortcut: cfg.doubleClickShortcut, button: h.button, at: loc)
        } else if cfg.doubleClick != .none {
            // Wait briefly to see whether a second click follows.
            firePendingClick() // never leave an earlier button's click dangling
            let run = { ActionRunner.run(cfg.click, shortcut: cfg.clickShortcut, button: h.button, at: loc) }
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.pendingClick != nil else { return } // already fired or superseded
                self.pendingClick = nil
                run()
            }
            pendingClick = (timer, run)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: timer)
        } else {
            ActionRunner.run(cfg.click, shortcut: cfg.clickShortcut, button: h.button, at: loc)
        }
    }

    /// Runs a delayed single click right away (used when the following press became a drag or hold).
    private func firePendingClick() {
        guard let p = pendingClick else { return }
        pendingClick = nil
        p.timer.cancel()
        p.run()
    }

    // MARK: Click and scroll

    private func modifiedScroll(_ h: Hold, event: CGEvent) {
        var ticks = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        if ticks == 0 { ticks = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) }
        guard ticks != 0 else { return }
        let reverse = config.scroll.reverse ? -1.0 : 1.0
        switch h.cfg.scroll {
        case .zoom: zoomStream.add(ticks * 0.08 * reverse)          // wheel up = zoom in
        case .rotate: rotateStream.add(ticks * 8 * reverse)
        case .switchSpaces:
            let now = CACurrentMediaTime()
            if now - lastSpaceStep > 0.25 {
                HotKeyPoster.post(ticks * reverse < 0 ? .moveRightASpace : .moveLeftASpace)  // wheel down = right
                lastSpaceStep = now
            }
        case .swiftScroll: _ = scrollEngine.handle(event, forced: .swift)
        case .preciseScroll: _ = scrollEngine.handle(event, forced: .precise)
        case .horizontalScroll: _ = scrollEngine.handle(event, forced: .horizontal)
        case .appSwitcher:
            let cmd = CGEventFlags.maskCommand.rawValue
            if !appSwitcherOpen {
                HotKeyPoster.postKeyEvent(55, down: true, flags: cmd)   // hold ⌘
                HotKeyPoster.postKeyEvent(48, down: true, flags: cmd); HotKeyPoster.postKeyEvent(48, down: false, flags: cmd)
                appSwitcherOpen = true
            } else {
                let flags = ticks * reverse > 0 ? cmd | CGEventFlags.maskShift.rawValue : cmd
                HotKeyPoster.postKeyEvent(48, down: true, flags: flags); HotKeyPoster.postKeyEvent(48, down: false, flags: flags)
            }
        case .off: break
        }
    }

    // MARK: Scroll output (drag-to-scroll + momentum)

    func postScroll(dx: Double, dy: Double, phase: ScrollPhase?, momentum: MomentumPhase = .none) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN scroll dx=\(dx) dy=\(dy) phase=\(String(describing: phase)) momentum=\(momentum)"); return }
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase?.rawValue ?? 0)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
        e.setIntegerValueField(.eventSourceUserData, value: HotKeyPoster.eventTag)
        if let cursor = CGEvent(source: nil)?.location { e.location = cursor }
        e.post(tap: .cgSessionEventTap)
    }

    private func startMomentum(vx: Double, vy: Double) {
        guard hypot(vx, vy) > 1 else { return }
        let m = Momentum(vx: vx, vy: vy)
        momentum = m
        var isFirstFrame = true
        var lastFrame = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] t in
            guard let self, self.momentum === m else { t.invalidate(); return }
            let now = CACurrentMediaTime()
            let dt = min(0.05, now - lastFrame); lastFrame = now
            // Trackpad-like deceleration: speed' = -30 · speed^0.7, stop at 1 px/s (Mac Mouse Fix values).
            let speed = hypot(m.vx, m.vy)
            let newSpeed = max(0, speed - 30 * pow(speed, 0.7) * dt)
            if newSpeed <= 1 { self.stopMomentum(); return }
            m.vx *= newSpeed / speed; m.vy *= newSpeed / speed
            let fx = m.vx * dt + m.remX, fy = m.vy * dt + m.remY
            let ix = fx.rounded(.towardZero), iy = fy.rounded(.towardZero)
            m.remX = fx - ix; m.remY = fy - iy
            self.postScroll(dx: ix, dy: iy, phase: nil, momentum: isFirstFrame ? .begin : .continue)
            isFirstFrame = false
        }
        RunLoop.main.add(t, forMode: .common)
        m.timer = t
    }

    private func stopMomentum() {
        guard let m = momentum else { return }
        m.timer?.invalidate()
        momentum = nil
        postScroll(dx: 0, dy: 0, phase: nil, momentum: .end)
    }
}
