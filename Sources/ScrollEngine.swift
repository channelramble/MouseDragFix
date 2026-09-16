import Cocoa

/// Scroll wheel handling modelled on Mac Mouse Fix 3's scroll pipeline:
///  - tick analysis: time between wheel notches → tick speed; groups of notches → "swipes"
///  - acceleration curve: pixels per notch from tick speed (minSens…maxSens per speed setting)
///  - fast-scroll speedup after several consecutive swipes
///  - animator: a linear "base" segment (110–180 ms, shorter for faster ticks) followed by a
///    drag/inertia tail; new notches add to the base distance left, so scrolling never jumps
///  - modifier keys: Shift = horizontal, Option = precise, Control = swift, Command = zoom
/// Trackpad and Magic Mouse (continuous) events are never touched.
final class ScrollEngine {
    enum Mode { case normal, horizontal, precise, swift }
    private var cfg: ScrollConfig { SettingsStore.shared.config.scroll }
    private let zoom = ZoomStream()

    // Tick analysis (Mac Mouse Fix constants)
    private let tickIntervalMax = 0.160          // slower than this = not consecutive
    private let tickIntervalAccelEnd = 0.015     // faster than this = max acceleration
    private let swipeMaxInterval = 0.375         // gap between swipes that still counts as consecutive
    private let swipeMinTickSpeed = 16.0         // ticks/s a swipe needs to count towards fast scroll
    private var lastTickTime: CFTimeInterval = 0
    private var consecutiveTicks = 0
    private var consecutiveSwipes = 0
    private var groupTickSpeedSum = 0.0
    private var lastDirection = (x: 0.0, y: 0.0)

    // Animator
    private struct Axis {
        var baseRemaining = 0.0    // px left in the linear base segment
        var baseSpeed = 0.0        // px/s during the base segment (signed)
        var dragSpeed = 0.0        // px/s during the inertia tail (signed)
        var carry = 0.0            // sub-pixel remainder
        var isIdle: Bool { baseRemaining == 0 && dragSpeed == 0 }
    }
    private var x = Axis(), y = Axis()
    private var timer: Timer?
    private var lastFrame: CFTimeInterval = 0
    private var sequenceOpen = false
    private var momentumOpen = false
    private var outFlags: CGEventFlags = []
    private var activeMode: Mode = .normal

    // MARK: Input

    /// Returns true when the event was consumed and replaced by our output.
    /// `forced` is set for click-and-scroll effects and bypasses the modifier-key logic.
    func handle(_ event: CGEvent, forced: Mode?) -> Bool {
        guard forced != nil || cfg.enabled else { return false }
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return false }
        // One notch per event. macOS inflates the delta for fast spins; Mac Mouse Fix only uses its sign
        // and derives the distance from tick timing, so we do the same.
        let rawY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let rawX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        guard rawX != 0 || rawY != 0 else { return false }
        if rawX != 0 && rawY != 0 { return false }               // diagonal (tilt + wheel): leave to the system
        var ticksY = Double(rawY.signum())
        var ticksX = Double(rawX.signum())

        let flags = event.flags
        var mode = forced ?? .normal
        var used: CGEventFlags = []
        if forced == nil {
            if flags.contains(.maskCommand), cfg.modZoom {
                if sequenceOpen || !x.isIdle || !y.isIdle { stopAnimation() }
                zoom.add(ticksY * (cfg.reverse ? -1 : 1))
                return true
            }
            if flags.contains(.maskControl), cfg.modSwift { mode = .swift; used = .maskControl }
            else if flags.contains(.maskAlternate), cfg.modPrecise { mode = .precise; used = .maskAlternate }
            else if flags.contains(.maskShift), cfg.modHorizontal { mode = .horizontal; used = .maskShift }
        }
        outFlags = CGEventFlags(rawValue: flags.rawValue & ~used.rawValue)
        if mode != activeMode { stopAnimation(); activeMode = mode }

        if cfg.reverse { ticksY = -ticksY; ticksX = -ticksX }
        if mode == .horizontal, ticksX == 0 { ticksX = ticksY; ticksY = 0 }

        // --- Tick analysis ---
        let now = CACurrentMediaTime()
        let dir = (x: ticksX.sign == .minus ? -1.0 : (ticksX == 0 ? 0 : 1.0),
                   y: ticksY.sign == .minus ? -1.0 : (ticksY == 0 ? 0 : 1.0))
        let directionChanged = (dir.x != 0 && lastDirection.x != 0 && dir.x != lastDirection.x)
            || (dir.y != 0 && lastDirection.y != 0 && dir.y != lastDirection.y)
        if directionChanged { consecutiveTicks = 0; consecutiveSwipes = 0; groupTickSpeedSum = 0; stopAnimation() }
        lastDirection = (dir.x != 0 ? dir.x : lastDirection.x, dir.y != 0 ? dir.y : lastDirection.y)

        var interval = now - lastTickTime
        if interval > tickIntervalMax || lastTickTime == 0 {
            // New group of notches. Did the previous group qualify as a swipe that continues a streak?
            let prevTicks = consecutiveTicks + 1
            let prevAvgSpeed = consecutiveTicks > 0 ? groupTickSpeedSum / Double(consecutiveTicks) : 0
            if prevTicks >= 2, interval <= swipeMaxInterval, prevAvgSpeed >= swipeMinTickSpeed {
                consecutiveSwipes += 1
            } else {
                consecutiveSwipes = 0
            }
            consecutiveTicks = 0
            groupTickSpeedSum = 0
            interval = tickIntervalMax
        } else {
            consecutiveTicks += 1
            groupTickSpeedSum += 1 / max(interval, tickIntervalAccelEnd)
        }
        lastTickTime = now
        let tickSpeed = 1 / max(interval, tickIntervalAccelEnd)                     // 6.25 … 66.7 ticks/s
        let speedNorm = min(1, max(0, (tickSpeed - 1 / tickIntervalMax) / (1 / tickIntervalAccelEnd - 1 / tickIntervalMax)))

        // --- Pixels for this notch ---
        var px: Double
        let precise = mode == .precise
        switch mode {
        case .swift:
            let screen = (NSScreen.main?.frame.height ?? 1080) * 0.85
            px = screen * 0.5 + (screen * 1.5 - screen * 0.5) * speedNorm
        case .precise:
            px = 10 + (20 - 10) * curve(speedNorm, curvature: 2.0)
        default:
            let (minSens, maxSens, curvature) = sensitivities()
            px = minSens + (maxSens - minSens) * curve(speedNorm, curvature: curvature)
            if !precise, consecutiveSwipes + 1 >= 3 {                                  // fast-scroll speedup
                let (p, c, b, t) = (1.33, 7.5, 1.1, 3.0)
                let a = (p - 1) / (pow(b, c) - 1)
                px *= a * pow(b, (Double(consecutiveSwipes + 1) - t) * c) + 1 - a
            }
        }
        let dx = ticksX * px, dy = ticksY * px

        // --- Output ---
        if cfg.smoothing == .off || precise {
            postScroll(dx: dx, dy: dy, phase: nil, momentum: nil)                  // plain, unanimated
            return true
        }
        let duration: Double
        switch mode {
        case .swift: duration = 0.300
        default: duration = cfg.smoothing == .high ? 0.220 : 0.180 + (0.110 - 0.180) * ((exp(4 * speedNorm) - 1) / (exp(4.0) - 1))
        }
        if momentumOpen { postScroll(dx: 0, dy: 0, phase: nil, momentum: .end); momentumOpen = false }
        if x.isIdle, y.isIdle { poster.resetLines() }
        if dx != 0 { addToAxis(&x, dx, duration: duration) }
        if dy != 0 { addToAxis(&y, dy, duration: duration) }
        ensureTimer()
        return true
    }

    /// Sensitivity (px per notch at slow / fastest ticks) and curve shape for the current settings.
    private func sensitivities() -> (Double, Double, Double) {
        let n: Double = cfg.speed == .low ? 0 : (cfg.speed == .medium ? 0.5 : 1)
        func lerp3(_ a: Double, _ b: Double, _ c: Double) -> Double { n < 0.5 ? a + (b - a) * n * 2 : b + (c - b) * (n - 0.5) * 2 }
        switch cfg.smoothing {
        case .off: return (lerp3(20, 30, 40), lerp3(40, 60, 80), lerp3(4.25, 3.0, 2.25))
        case .regular: return (lerp3(30, 60, 120), lerp3(90, 120, 180), lerp3(0.25, 0, 0))
        case .high: return (lerp3(60, 90, 150), lerp3(120, 180, 240), 0)
        }
    }

    /// Eases the 0…1 tick-speed position; `curvature` > 0 favours medium speeds like Mac Mouse Fix's capped Bezier.
    private func curve(_ t: Double, curvature: Double) -> Double {
        curvature <= 0 ? t : 1 - pow(1 - t, 1 + curvature)
    }

    private func addToAxis(_ a: inout Axis, _ px: Double, duration: Double) {
        // Only the *base* distance left carries over; the inertia tail is discarded (as in Mac Mouse Fix).
        var dist = a.baseRemaining + px
        if a.baseRemaining != 0, a.baseRemaining.sign != px.sign { dist = px }
        a.baseRemaining = dist
        a.baseSpeed = dist / duration
        a.dragSpeed = 0
    }

    /// Ends any open sequence immediately (e.g. when the modifier button is released).
    func flush() { stopAnimation() }

    // MARK: Animation

    private func ensureTimer() {
        guard timer == nil else { return }
        lastFrame = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastFrame)
        lastFrame = now
        let high = cfg.smoothing == .high || activeMode == .swift
        let (dragExp, dragCoef, stopSpeed) = high ? (0.7, 40.0, 30.0) : (1.0, 23.0, 30.0)

        let baseActive = x.baseRemaining != 0 || y.baseRemaining != 0
        let sx = step(&x, dt: dt, dragExp: dragExp, dragCoef: dragCoef, stopSpeed: stopSpeed)
        let sy = step(&y, dt: dt, dragExp: dragExp, dragCoef: dragCoef, stopSpeed: stopSpeed)

        if !high {
            // Regular smoothness: plain continuous pixel events without gesture phases, exactly like
            // Mac Mouse Fix's "ContinuousScroll" output. Phased (trackpad-like) events make browsers
            // rubber-band at the page edges while the animation is still running.
            if sx != 0 || sy != 0 { postScroll(dx: sx, dy: sy, phase: nil, momentum: nil) }
        } else if baseActive {
            if sx != 0 || sy != 0 || !sequenceOpen {
                postScroll(dx: sx, dy: sy, phase: sequenceOpen ? .changed : .began, momentum: nil)
                sequenceOpen = true
            }
        } else {
            // High smoothness: the inertia tail is sent as trackpad momentum scrolling.
            if sequenceOpen { postScroll(dx: 0, dy: 0, phase: .ended, momentum: nil); sequenceOpen = false }
            if sx != 0 || sy != 0 || !momentumOpen {
                postScroll(dx: sx, dy: sy, phase: nil, momentum: momentumOpen ? .continue : .begin)
                momentumOpen = true
            }
        }
        if x.isIdle, y.isIdle { stopAnimation() }
    }

    private func step(_ a: inout Axis, dt: Double, dragExp: Double, dragCoef: Double, stopSpeed: Double) -> Double {
        var out = 0.0
        if a.baseRemaining != 0 {
            var s = a.baseSpeed * dt
            if abs(s) >= abs(a.baseRemaining) { s = a.baseRemaining }
            a.baseRemaining -= s
            out = s
            if a.baseRemaining == 0 { a.dragSpeed = a.baseSpeed }
        } else if a.dragSpeed != 0 {
            out = a.dragSpeed * dt
            let v = abs(a.dragSpeed)
            let nv = v - dragCoef * pow(v, dragExp) * dt
            a.dragSpeed = nv <= stopSpeed ? 0 : nv * (a.dragSpeed < 0 ? -1 : 1)
        }
        let f = out + a.carry
        let i = f.rounded(.towardZero)
        a.carry = f - i
        return i
    }

    private func stopAnimation() {
        if sequenceOpen { postScroll(dx: 0, dy: 0, phase: .ended, momentum: nil); sequenceOpen = false }
        if momentumOpen { postScroll(dx: 0, dy: 0, phase: nil, momentum: .end); momentumOpen = false }
        x = Axis(); y = Axis()
        timer?.invalidate(); timer = nil
    }

    // MARK: Output

    private let poster = ScrollPoster()

    /// All wheel output goes through the shared poster, so line deltas are sub-pixelated exactly as
    /// Mac Mouse Fix does instead of being rounded up to a whole line on every frame.
    private func postScroll(dx: Double, dy: Double, phase: GestureEngine.ScrollPhase?, momentum: GestureEngine.MomentumPhase?) {
        poster.post(dx: dx, dy: dy, phase: phase, momentum: momentum ?? .none, flags: outFlags)
    }
}
