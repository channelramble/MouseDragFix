import Cocoa

/// Posts real three-finger "dock swipe" gestures the way macOS 27 still accepts them:
/// an IOHIDEvent of type DockSwipe attached to a CGEvent through SkyLight's
/// SLEventSetIOHIDEvent. WindowServer then animates Spaces / Mission Control in lockstep
/// with the drag, exactly like a trackpad (and like Mac Mouse Fix's macOS 27 code path).
final class DockSwipe {
    static let shared = DockSwipe()

    enum Kind: Int { case horizontal = 1, vertical = 2 }
    enum Phase: UInt32 { case began = 1, changed = 2, ended = 4, cancelled = 8 }

    private typealias EvCreate = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias EvSetInt = @convention(c) (CFTypeRef, UInt32, Int) -> Void
    private typealias EvSetDouble = @convention(c) (CFTypeRef, UInt32, Double) -> Void
    private typealias EvAppend = @convention(c) (CFTypeRef, CFTypeRef, UInt32) -> Void
    private typealias SetHID = @convention(c) (CGEvent, CFTypeRef) -> Void
    private typealias MainCID = @convention(c) () -> Int32
    private typealias CopyManaged = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let create: EvCreate?, setInt: EvSetInt?, setDouble: EvSetDouble?, append: EvAppend?
    private let setHID: SetHID?, mainCID: MainCID?, copyManaged: CopyManaged?
    let available: Bool

    // IOHIDEvent constants (IOHIDEventTypes.h): field = type << 16 | index
    private let typeDockSwipe: UInt32 = 23, typeVelocity: UInt32 = 9
    private let fieldMotion: UInt32 = 23 << 16 | 1, fieldProgress: UInt32 = 23 << 16 | 2, fieldFlavor: UInt32 = 23 << 16 | 5
    private let fieldVelX: UInt32 = 9 << 16 | 0, fieldVelY: UInt32 = 9 << 16 | 1, fieldVelZ: UInt32 = 9 << 16 | 2
    private let flavorDockPrimary = 3
    private let phaseShift: UInt32 = 24
    private let spaceSeparatorWidth = 63.0

    private var kind: Kind = .horizontal
    private var scale = 0.001
    private var offset = 0.0, lastDelta = 0.0
    private var started = false
    private var resendTimers: [Timer] = []
    private(set) var isActive = false
    private var pendingDelta = 0.0
    private var frameTimer: Timer?
    private var lastInputDelta = 0.0   // progress from the last single mouse report (drives the exit velocity)

    private init() {
        func sym<T>(_ lib: String, _ name: String, _: T.Type) -> T? {
            guard let h = dlopen(lib, RTLD_LAZY), let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        let iokit = "/System/Library/Frameworks/IOKit.framework/IOKit"
        let sky = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        create = sym(iokit, "IOHIDEventCreate", EvCreate.self)
        setInt = sym(iokit, "IOHIDEventSetIntegerValue", EvSetInt.self)
        setDouble = sym(iokit, "IOHIDEventSetDoubleValue", EvSetDouble.self)
        append = sym(iokit, "IOHIDEventAppendEvent", EvAppend.self)
        setHID = sym(sky, "SLEventSetIOHIDEvent", SetHID.self)
        mainCID = sym(sky, "SLSMainConnectionID", MainCID.self)
        copyManaged = sym(sky, "SLSCopyManagedDisplaySpaces", CopyManaged.self)
        available = create != nil && setInt != nil && setDouble != nil && append != nil && setHID != nil
    }

    // MARK: Gesture lifecycle

    /// Starts a gesture. `scaleMultiplier` 1.0 makes Spaces follow the pointer exactly.
    func begin(kind: Kind, at pointer: CGPoint, scaleMultiplier: Double) {
        resendTimers.forEach { $0.invalidate() }; resendTimers.removeAll()
        self.kind = kind
        offset = 0; lastDelta = 0; started = false; isActive = true
        pendingDelta = 0; lastInputDelta = 0
        frameTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.flush() }
        RunLoop.main.add(t, forMode: .common)
        frameTimer = t

        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: pointer.x, y: NSScreen.screens[0].frame.maxY - pointer.y), $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = screen.frame.size
        switch kind {
        case .horizontal:
            // Same scaling Mac Mouse Fix arrived at empirically: one Space == this much "progress".
            let n = max(1, spaceCount(for: screen))
            let progressPerSpace = n == 1 ? 2.0 : 1.0 + 1.0 / Double(n - 1)
            scale = progressPerSpace / (size.width + spaceSeparatorWidth) * scaleMultiplier
        case .vertical:
            scale = 1.0 / size.height * scaleMultiplier
        }
        Log.debug("dockswipe begin kind=\(kind) spaces=\(spaceCount(for: screen)) scale=\(scale)")
    }

    /// Feeds pointer movement. Drag left reveals the Space on the right; drag up opens Mission Control.
    func update(dx: Double, dy: Double) {
        guard isActive else { return }
        let d = kind == .horizontal ? dx * scale : -dy * scale
        pendingDelta += d
        if d != 0 { lastInputDelta = d }
        if !started { flush() }   // first movement goes out immediately so the gesture begins without delay
    }

    /// Posts the accumulated movement as a single gesture event (called once per frame).
    private func flush() {
        guard isActive else { return }
        let d = pendingDelta
        pendingDelta = 0
        if d == 0 && started { return }
        offset += d
        // Exit velocity must come from one mouse report, not a whole coalesced frame, or WindowServer
        // gets an 8× flick at 1000 Hz and overshoots.
        lastDelta = lastInputDelta
        post(phase: started ? .changed : .began)
        started = true
    }

    /// Ends the gesture. Reversing direction right before release cancels (snaps back), like a trackpad.
    func end() {
        guard isActive else { return }
        flush()
        frameTimer?.invalidate(); frameTimer = nil
        isActive = false
        guard started else { return }
        let phase: Phase = (lastDelta.sign == offset.sign) ? .ended : .cancelled
        post(phase: phase)
        // WindowServer occasionally misses a lone end event; Mac Mouse Fix re-sends it twice.
        for delay in [0.2, 0.5] {
            let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.post(phase: phase) }
            RunLoop.main.add(t, forMode: .common)
            resendTimers.append(t)
        }
    }

    // MARK: Posting

    private func post(phase: Phase) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN dockswipe kind=\(kind) phase=\(phase) offset=\(String(format: "%.3f", offset)) exitSpeed=\(String(format: "%.2f", lastDelta * 100))"); return }
        guard let create, let setInt, let setDouble, let append, let setHID,
              let ev = create(nil, typeDockSwipe, 0, phase.rawValue << phaseShift)?.takeRetainedValue() else { return }
        setInt(ev, fieldMotion, kind.rawValue)
        setInt(ev, fieldFlavor, flavorDockPrimary)
        setDouble(ev, fieldProgress, offset)
        if phase == .ended || phase == .cancelled, let child = create(nil, typeVelocity, 0, 0)?.takeRetainedValue() {
            let exitSpeed = lastDelta * 100
            setDouble(child, fieldVelX, exitSpeed); setDouble(child, fieldVelY, exitSpeed); setDouble(child, fieldVelZ, 0)
            append(ev, child, 0)
        }
        guard let cg = CGEvent(source: nil) else { return }
        cg.type = unsafeBitCast(UInt32(30), to: CGEventType.self) // NSEventTypeMagnify carrier, as Mac Mouse Fix uses
        cg.setIntegerValueField(.eventSourceUserData, value: HotKeyPoster.eventTag)
        setHID(cg, ev)
        cg.post(tap: .cgSessionEventTap)
    }

    /// Number of Spaces on the given display (falls back to counting all displays' Spaces).
    private func spaceCount(for screen: NSScreen) -> Int {
        guard let mainCID, let copyManaged,
              let displays = copyManaged(mainCID())?.takeRetainedValue() as? [[String: Any]] else { return 1 }
        let uuid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .flatMap { CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID($0.uint32Value))?.takeRetainedValue() }
            .map { CFUUIDCreateString(nil, $0) as String }
        for d in displays {
            if let id = d["Display Identifier"] as? String, id == uuid, let spaces = d["Spaces"] as? [[String: Any]] {
                return spaces.count
            }
        }
        return displays.reduce(0) { $0 + (($1["Spaces"] as? [[String: Any]])?.count ?? 0) }
    }
}
