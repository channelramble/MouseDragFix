import Foundation

/// Pointer speed and acceleration, applied per mouse through the HID event system
/// (the same properties Mac Mouse Fix and LinearMouse set). Originals are restored on quit.
final class PointerSpeed {
    static let shared = PointerSpeed()

    private typealias ClientCreate = @convention(c) (CFAllocator?, Int32, UnsafeRawPointer?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias SetProperty = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias MatchingBlock = @convention(block) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, CFTypeRef) -> Void
    private typealias RegisterMatching = @convention(c) (CFTypeRef, @escaping MatchingBlock, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias Schedule = @convention(c) (CFTypeRef, CFRunLoop, CFString) -> Void

    private let clientCreate: ClientCreate?, setMatching: SetMatching?, copyServices: CopyServices?
    private let setProperty: SetProperty?, copyProperty: CopyProperty?, registerMatching: RegisterMatching?, schedule: Schedule?
    private var client: CFTypeRef?
    private var originals: [String: (resolution: CFTypeRef?, acceleration: CFTypeRef?)] = [:]
    private var current: PointerConfig?

    private let resolutionKey = "HIDPointerResolution" as CFString
    private let accelerationKey = "HIDMouseAcceleration" as CFString
    private let clientTypePassive: Int32 = 2

    private init() {
        let lib = "/System/Library/Frameworks/IOKit.framework/IOKit"
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let h = dlopen(lib, RTLD_LAZY), let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        clientCreate = sym("IOHIDEventSystemClientCreateWithType", ClientCreate.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatching.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServices.self)
        setProperty = sym("IOHIDServiceClientSetProperty", SetProperty.self)
        copyProperty = sym("IOHIDServiceClientCopyProperty", CopyProperty.self)
        registerMatching = sym("IOHIDEventSystemClientRegisterDeviceMatchingBlock", RegisterMatching.self)
        schedule = sym("IOHIDEventSystemClientScheduleWithRunLoop", Schedule.self)
    }

    var available: Bool { clientCreate != nil && setMatching != nil && copyServices != nil && setProperty != nil }

    func apply(_ config: PointerConfig) {
        current = config
        if config.useSystemSettings { restore(); return }
        guard ensureClient() else { return }
        for service in mouseServices() { apply(config, to: service) }
    }

    /// If a previous instance died without restoring (SIGTERM, logout), put the saved originals back.
    func restoreLeftoversFromPreviousRun() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: [String: Int]], !saved.isEmpty,
              ensureClient(), let setProperty else { return }
        for service in mouseServices() {
            guard let o = saved[identify(service)] else { continue }
            _ = setProperty(service, resolutionKey, NSNumber(value: o["resolution"] ?? 400 * 65536))
            _ = setProperty(service, accelerationKey, NSNumber(value: o["acceleration"] ?? Int(systemAcceleration * 65536)))
        }
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        Log.info("restored pointer settings left over from a previous run")
    }
    private static let savedKey = "pointerOriginals"

    /// Puts every mouse back to what it had before we touched it.
    func restore() {
        guard !originals.isEmpty, let setProperty else { return }
        for service in mouseServices() {
            guard let orig = originals[identify(service)] else { continue }
            _ = setProperty(service, resolutionKey, orig.resolution ?? fixed(400) as CFTypeRef)
            _ = setProperty(service, accelerationKey, orig.acceleration ?? fixed(systemAcceleration) as CFTypeRef)
        }
        originals.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        Log.info("pointer settings restored")
    }

    // MARK: Internals

    private func ensureClient() -> Bool {
        if client != nil { return true }
        guard let clientCreate, let setMatching, let c = clientCreate(nil, clientTypePassive, nil)?.takeRetainedValue() else {
            Log.info("HID event system client unavailable; pointer settings not applied")
            return false
        }
        setMatching(c, ["PrimaryUsagePage": 1, "PrimaryUsage": 2] as CFDictionary)   // generic desktop / mouse
        if let registerMatching, let schedule {
            registerMatching(c, { [weak self] _, _, service in
                guard let self, let cfg = self.current, !cfg.useSystemSettings else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.apply(cfg, to: service) }
            }, nil, nil)
            schedule(c, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        client = c
        return true
    }

    private func mouseServices() -> [CFTypeRef] {
        guard let client, let copyServices, let arr = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return arr
    }

    private func apply(_ config: PointerConfig, to service: CFTypeRef) {
        guard let setProperty, let copyProperty else { return }
        let id = identify(service)
        if originals[id] == nil {
            let res = copyProperty(service, resolutionKey)?.takeRetainedValue()
            let acc = copyProperty(service, accelerationKey)?.takeRetainedValue()
            originals[id] = (res, acc)
            var saved = (UserDefaults.standard.dictionary(forKey: Self.savedKey) as? [String: [String: Int]]) ?? [:]
            saved[id] = ["resolution": (res as? NSNumber)?.intValue ?? 400 * 65536,
                         "acceleration": (acc as? NSNumber)?.intValue ?? Int(systemAcceleration * 65536)]
            UserDefaults.standard.set(saved, forKey: Self.savedKey)
        }
        // Resolution scales speed (higher resolution = slower); acceleration must be set right after.
        let sensitivity = min(3, max(0.25, config.sensitivity))
        let okRes = setProperty(service, resolutionKey, fixed(400.0 / sensitivity) as CFTypeRef)
        let okAcc = setProperty(service, accelerationKey, fixed(min(3, max(0, config.acceleration))) as CFTypeRef)
        Log.debug("pointer \(id): resolution ok=\(okRes) acceleration ok=\(okAcc)")
    }

    private func identify(_ service: CFTypeRef) -> String {
        guard let copyProperty else { return "?" }
        let keys = ["Product", "VendorID", "ProductID", "LocationID"]
        return keys.map { k in
            (copyProperty(service, k as CFString)?.takeRetainedValue()).map { "\($0)" } ?? "-"
        }.joined(separator: "/")
    }

    private func fixed(_ v: Double) -> NSNumber { NSNumber(value: Int32((v * 65536.0).rounded())) }

    private var systemAcceleration: Double {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"] as? Double) ?? 0.6875
    }
}
