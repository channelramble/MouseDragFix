import Foundation
import CoreGraphics

/// The system-wide "symbolic hot keys" macOS uses for Mission Control features
/// (System Settings → Keyboard → Keyboard Shortcuts → Mission Control).
enum SymbolicHotKey: Int32 {
    case missionControl = 32
    case appExpose = 33
    case showDesktop = 36
    case moveLeftASpace = 79
    case moveRightASpace = 81
    case launchpad = 160
    case lookUp = 70
    case appSwitcher = 71
    case spotlight = 64
    case notificationCenter = 163

    var name: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .moveLeftASpace: return "Move left a Space"
        case .moveRightASpace: return "Move right a Space"
        case .launchpad: return "Launchpad"
        case .lookUp: return "Look Up"
        case .appSwitcher: return "App Switcher"
        case .spotlight: return "Spotlight"
        case .notificationCenter: return "Notification Center"
        }
    }

    /// Apple's factory bindings, used only if the SkyLight lookup is unavailable.
    var factoryKey: (vkc: UInt16, mods: UInt64) {
        let ctrl: UInt64 = CGEventFlags.maskControl.rawValue
        switch self {
        case .missionControl: return (126, ctrl)     // ⌃↑
        case .appExpose: return (125, ctrl)          // ⌃↓
        case .showDesktop: return (103, 0)           // F11
        case .moveLeftASpace: return (123, ctrl)     // ⌃←
        case .moveRightASpace: return (124, ctrl)    // ⌃→
        case .launchpad: return (131, 0)             // F4-style Launchpad key
        case .lookUp: return (2, ctrl | CGEventFlags.maskCommand.rawValue) // ⌃⌘D
        case .appSwitcher: return (48, CGEventFlags.maskCommand.rawValue)  // ⌘⇥
        case .spotlight: return (49, CGEventFlags.maskCommand.rawValue)    // ⌘Space
        case .notificationCenter: return (0xFFFF, 0)
        }
    }
}

/// Bridges to the private SkyLight symbolic-hotkey API (same approach as Mac Mouse Fix's
/// "symbolicHotkey" actions and its macOS 27 workaround). Resolved with dlsym so the
/// binary never links a private framework directly.
enum SkyLight {
    typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias SetValue = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let h = handle, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    static let getValue = sym("CGSGetSymbolicHotKeyValue", GetValue.self)
    static let setValue = sym("CGSSetSymbolicHotKeyValue", SetValue.self)
    static let isEnabled = sym("CGSIsSymbolicHotKeyEnabled", IsEnabled.self)
    static let setEnabled = sym("CGSSetSymbolicHotKeyEnabled", SetEnabled.self)
    static var available: Bool { getValue != nil && setValue != nil && isEnabled != nil && setEnabled != nil }
}

enum HotKeyPoster {
    static let eventTag: Int64 = 0x4D44_4658 // 'MDFX' — marks events we synthesize
    static let dryRun = ProcessInfo.processInfo.environment["MDF_DRYRUN"] != nil
    static let keyEquivalentNull: UInt16 = 0xFFFF
    static let vkcNull: UInt16 = 0xFFFF
    static let vkcOutOfReach: UInt16 = 400 // never produced by a real keyboard

    /// Triggers a Mission Control feature by pressing whatever shortcut it is bound to.
    /// If the shortcut is disabled or unbound, a permanent but unreachable binding is
    /// created (fn + numpad modifiers with a key code no keyboard has) so real keys stay untouched.
    static func post(_ hk: SymbolicHotKey) {
        if dryRun { Log.info("DRYRUN hotkey: \(hk.name)"); return }

        guard SkyLight.available, let getValue = SkyLight.getValue, let isEnabled = SkyLight.isEnabled,
              let setValue = SkyLight.setValue, let setEnabled = SkyLight.setEnabled else {
            Log.info("SkyLight unavailable, using factory shortcut for \(hk.name)")
            let k = hk.factoryKey
            postKey(k.vkc, flags: k.mods)
            return
        }

        var keq: UInt16 = keyEquivalentNull, vkc: UInt16 = vkcNull, mods: UInt32 = 0
        let err = getValue(hk.rawValue, &keq, &vkc, &mods)
        let enabled = isEnabled(hk.rawValue)
        Log.debug("hotkey \(hk.name): err=\(err) enabled=\(enabled) keq=\(keq) vkc=\(vkc) mods=0x\(String(mods, radix: 16))")

        if err == 0, enabled, vkc != vkcNull {
            postKey(vkc, flags: UInt64(mods))
            return
        }

        // Shortcut is off or unusable: install an unreachable one and enable it.
        _ = setEnabled(hk.rawValue, true)
        let newVKC = vkcOutOfReach + UInt16(hk.rawValue)
        let newMods: UInt32 = (1 << 21) | (1 << 23) // numeric pad | fn
        let setErr = setValue(hk.rawValue, keyEquivalentNull, newVKC, newMods)
        Log.info("installed fallback binding for \(hk.name) (err=\(setErr))")
        postKey(newVKC, flags: UInt64(newMods))
    }

    /// Posts a single key-down or key-up with the given modifier flags.
    static func postKeyEvent(_ vkc: UInt16, down: Bool, flags: UInt64) {
        if dryRun { Log.info("DRYRUN keyevent vkc=\(vkc) down=\(down) flags=0x\(String(flags, radix: 16))"); return }
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: vkc, keyDown: down) else { return }
        e.flags = CGEventFlags(rawValue: flags)
        e.setIntegerValueField(.eventSourceUserData, value: eventTag)
        e.post(tap: .cgSessionEventTap)
    }

    /// Presses and releases a key with the given modifier flags.
    static func postKey(_ vkc: UInt16, flags: UInt64) {
        if dryRun { Log.info("DRYRUN key: vkc=\(vkc) flags=0x\(String(flags, radix: 16))"); return }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: vkc, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: vkc, keyDown: false) else { return }
        let physical = CGEventSource.flagsState(.combinedSessionState) // real modifier state, restored on key-up
        down.flags = CGEventFlags(rawValue: flags)
        up.flags = physical
        for e in [down, up] {
            e.setIntegerValueField(.eventSourceUserData, value: eventTag)
            e.post(tap: .cgSessionEventTap)
        }
    }
}

enum Log {
    static let verbose = ProcessInfo.processInfo.environment["MDF_DEBUG"] != nil
    static func info(_ s: String) { FileHandle.standardError.write(("[MouseDragFix] " + s + "\n").data(using: .utf8)!) }
    static func debug(_ s: String) { if verbose { info(s) } }
}
