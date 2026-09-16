import Cocoa

/// Trackpad gestures that are delivered to apps (not to WindowServer): pinch, rotate,
/// smart zoom, navigation swipe. Posted with the same private CGEvent fields Mac Mouse Fix uses.
/// Pinch-zoom for the scroll-wheel Zoom effects, following Mac Mouse Fix.
///
/// Magnification is pixels / 800, and one wheel notch is animated over 250 ms at 120 Hz the way
/// Mac Mouse Fix animates its touch-driver curve. Emitting the zoom in a few large steps instead
/// makes it visibly jagged, since each event is an instant scale change in the receiving app.
final class ZoomStream {
    private let duration = 0.25                       // Mac Mouse Fix animates one notch over 250 ms
    private let frameInterval = 1.0 / 120.0
    private let pixelsPerNotch = 90.0
    private let pixelsPerMagnification = 800.0
    /// Chromium swallows this much magnification at the start of each pinch before it reacts at all
    /// (measured: 0.3 spread over a gesture produces no zoom in Brave). Mac Mouse Fix pays it off in a
    /// single event, which is invisible precisely because it is swallowed, and the animation after it
    /// then zooms smoothly. Paying it gradually instead just delays the start.
    private let chromiumKickIn = 380.0 / 800.0
    private let chromiumKickOut = -250.0 / 800.0
    /// Consecutive notches must land inside one gesture, or each one pays the dead zone again and the
    /// zoom lurches instead of gliding.
    private let idleBeforeEnd = 0.25

    private let queue = DispatchQueue(label: "com.wateruse.MouseDragFix.zoom", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var remaining = 0.0        // magnification still to deliver
    private var speed = 0.0            // magnification per second
    private var open = false
    private var pendingKick = 0.0     // Chromium dead-zone payment for the gesture about to start
    private var idleSince: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0

    /// `notches` is signed: positive zooms in. Called from the event tap on the main thread.
    func add(_ notches: Double) {
        guard notches != 0 else { return }
        let delta = notches * pixelsPerNotch / pixelsPerMagnification
        // Decide on the main thread, where looking up the window under the pointer is safe.
        let kick = (timer == nil && !open && ZoomStream.chromiumUnderPointer())
            ? (delta > 0 ? chromiumKickIn : chromiumKickOut) : 0
        queue.async { [self] in
            if kick != 0, !open { pendingKick = kick }
            if remaining != 0, remaining.sign != delta.sign { remaining = 0 }   // reversing direction
            remaining += delta
            speed = remaining / duration                                        // linear restart
            idleSince = CACurrentMediaTime()
            if timer == nil {
                lastFrame = idleSince
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now() + frameInterval, repeating: frameInterval, leeway: .milliseconds(1))
                t.setEventHandler { [weak self] in self?.frame() }
                t.resume()
                timer = t
            }
        }
    }

    func finish() {
        queue.async { [self] in
            if open { Gestures.magnify(0, phase: 4); open = false }
            remaining = 0; speed = 0; pendingKick = 0
            timer?.cancel(); timer = nil
        }
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(4 * frameInterval, max(0.001, now - lastFrame))
        lastFrame = now

        if remaining != 0 {
            var step = speed * dt
            if abs(step) >= abs(remaining) { step = remaining }
            remaining -= step
            if open {
                Gestures.magnify(step, phase: 2)
            } else {
                Gestures.magnify(step, phase: 1)
                if pendingKick != 0 {
                    Gestures.magnify(step + pendingKick, phase: 2)   // swallowed by Chromium
                    pendingKick = 0
                }
                open = true
            }
            idleSince = now
        } else if open, now - idleSince > idleBeforeEnd {
            Gestures.magnify(0, phase: 4)
            open = false
            timer?.cancel(); timer = nil
        } else if !open {
            timer?.cancel(); timer = nil
        }
    }

    /// Bundle identifier of the window under the pointer, matched against the Chromium family.
    private static func chromiumUnderPointer() -> Bool {
        let ids = ["com.google.Chrome", "org.chromium.Chromium", "company.thebrowser.Browser",
                   "com.operasoftware.Opera", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
                   "com.brave.Browser"]
        guard let bundle = bundleIDUnderPointer() else { return false }
        return ids.contains { bundle.contains($0) }
    }

    private static func bundleIDUnderPointer() -> String? {
        guard let cursor = CGEvent(source: nil)?.location,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for w in windows {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if rect.contains(cursor) { return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
        }
        return nil
    }
}

enum Gestures {
    static let tag = HotKeyPoster.eventTag
    private static func field(_ n: UInt32) -> CGEventField { unsafeBitCast(n, to: CGEventField.self) } // private field ids have no Swift case

    private static func gestureEvent(hidType: Int64) -> CGEvent? {
        guard let e = CGEvent(source: nil) else { return nil }
        e.type = unsafeBitCast(UInt32(29), to: CGEventType.self)   // NSEventTypeGesture
        e.setIntegerValueField(field(110), value: hidType)          // IOHIDEvent subtype
        e.setIntegerValueField(.eventSourceUserData, value: tag)
        if let cursor = CGEvent(source: nil)?.location { e.location = cursor }
        return e
    }

    /// phase: 1 began, 2 changed, 4 ended
    static func magnify(_ magnification: Double, phase: Int64) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN magnify \(magnification) phase=\(phase)"); return }
        guard let e = gestureEvent(hidType: 8) else { return }      // kIOHIDEventTypeZoom
        e.setIntegerValueField(field(132), value: phase)
        e.setDoubleValueField(field(113), value: magnification)
        e.post(tap: .cghidEventTap)
    }

    static func rotate(_ degrees: Double, phase: Int64) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN rotate \(degrees) phase=\(phase)"); return }
        guard let e = gestureEvent(hidType: 5) else { return }      // kIOHIDEventTypeRotation
        e.setIntegerValueField(field(132), value: phase)
        e.setDoubleValueField(field(114), value: degrees)
        e.post(tap: .cghidEventTap)
    }

    static func smartZoom() {
        if HotKeyPoster.dryRun { Log.info("DRYRUN smart zoom"); return }
        guard let e = gestureEvent(hidType: 22) else { return }     // kIOHIDEventTypeZoomToggle
        e.post(tap: .cghidEventTap)
    }

    enum SwipeDirection: Int64 { case up = 1, down = 2, left = 4, right = 8 }
    static func navigationSwipe(_ direction: SwipeDirection) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN navigation swipe \(direction)"); return }
        guard let e = gestureEvent(hidType: 16) else { return }     // kIOHIDEventTypeNavigationSwipe
        e.setIntegerValueField(field(132), value: 1)
        e.setIntegerValueField(field(115), value: direction.rawValue)
        e.post(tap: .cghidEventTap)
        e.setIntegerValueField(field(115), value: 0)
        e.setIntegerValueField(field(132), value: 4)
        e.post(tap: .cghidEventTap)
    }
}

/// Animates a continuous gesture value (pinch amount, rotation) towards a target and closes
/// the began…ended sequence after the input stops.
final class GestureStream {
    enum Kind { case magnify, rotate }
    let kind: Kind
    private var remaining = 0.0
    private var open = false
    private var timer: Timer?
    private var idleSince: CFTimeInterval = 0
    init(kind: Kind) { self.kind = kind }

    func add(_ delta: Double) {
        guard delta != 0 else { return }
        if remaining.sign != delta.sign { remaining = 0 }
        remaining += delta
        idleSince = CACurrentMediaTime()
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func finish() {
        if open { post(0, phase: 4); open = false }
        remaining = 0
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        if remaining != 0 {
            let k = 1 - exp(-(1.0 / 120.0) / 0.07)
            var step = remaining * k
            if abs(remaining) < (kind == .magnify ? 0.002 : 0.2) { step = remaining }
            remaining -= step
            post(step, phase: open ? 2 : 1)
            open = true
        } else if open, CACurrentMediaTime() - idleSince > 0.1 {
            finish()
        }
    }

    private func post(_ v: Double, phase: Int64) {
        switch kind {
        case .magnify: Gestures.magnify(v, phase: phase)
        case .rotate: Gestures.rotate(v, phase: phase)
        }
    }
}
