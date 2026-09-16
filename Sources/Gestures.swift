import Cocoa

/// Trackpad gestures that are delivered to apps (not to WindowServer): pinch, rotate,
/// smart zoom, navigation swipe. Posted with the same private CGEvent fields Mac Mouse Fix uses.
/// Pinch-zoom for the scroll-wheel Zoom effects, following Mac Mouse Fix.
///
/// Magnification is animated pixels / 800. Chromium browsers swallow a large amount of pinch before
/// they begin zooming at all, so like Mac Mouse Fix we detect them under the pointer and add a big
/// kick to the first event of each gesture; without it, wheel zoom appears to do nothing in Chrome,
/// Brave, Edge, Vivaldi, Opera and Arc.
final class ZoomStream {
    /// Pixels of scroll one wheel notch is worth, converted to magnification by Mac Mouse Fix's /800.
    private let pixelsPerNotch = 90.0
    private let pixelsPerMagnification = 800.0
    private let chromiumKickIn = 380.0 / 800.0
    private let chromiumKickOut = -250.0 / 800.0
    /// Consecutive notches must stay inside one gesture; otherwise every notch re-applies the
    /// Chromium kick and the page zooms far too fast.
    private let idleBeforeEnd = 0.25

    private var remaining = 0.0
    private var open = false
    private var chromium = false
    private var timer: Timer?
    private var idleSince: CFTimeInterval = 0

    /// `notches` is signed: positive zooms in.
    func add(_ notches: Double) {
        guard notches != 0 else { return }
        let delta = notches * pixelsPerNotch / pixelsPerMagnification
        if remaining != 0, remaining.sign != delta.sign { remaining = 0 }
        remaining += delta
        idleSince = CACurrentMediaTime()
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func finish() {
        if open { Gestures.magnify(0, phase: 4); open = false }
        remaining = 0
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        if remaining != 0 {
            var step = remaining * 0.5
            if abs(remaining) < 0.004 { step = remaining }
            remaining -= step
            if !open {
                chromium = ZoomStream.chromiumUnderPointer()
                Gestures.magnify(step, phase: 1)
                if chromium {
                    // Chromium ignores the first delta and needs a lot of pinch before it reacts.
                    Gestures.magnify(step + (step > 0 ? chromiumKickIn : chromiumKickOut), phase: 2)
                }
                open = true
            } else {
                Gestures.magnify(step, phase: 2)
            }
        } else if open, CACurrentMediaTime() - idleSince > idleBeforeEnd {
            finish()
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
            if rect.contains(cursor) {
                return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
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
