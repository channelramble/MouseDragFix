import Cocoa

/// Executes a configured button action.
enum ActionRunner {
    static func run(_ action: ButtonAction, shortcut: KeyShortcut?, button: Int, at location: CGPoint) {
        Log.debug("action \(action) button=\(button)")
        switch action {
        case .none: break
        case .passThrough: click(button: button, at: location)
        case .middleClick: click(button: 2, at: location)
        case .back: HotKeyPoster.postKey(33, flags: CGEventFlags.maskCommand.rawValue)     // ⌘[
        case .forward: HotKeyPoster.postKey(30, flags: CGEventFlags.maskCommand.rawValue)  // ⌘]
        case .missionControl: HotKeyPoster.post(.missionControl)
        case .appExpose: HotKeyPoster.post(.appExpose)
        case .showDesktop: HotKeyPoster.post(.showDesktop)
        case .launchpad: HotKeyPoster.post(.launchpad)
        case .moveLeftSpace: HotKeyPoster.post(.moveLeftASpace)
        case .moveRightSpace: HotKeyPoster.post(.moveRightASpace)
        case .lookUp: HotKeyPoster.post(.lookUp)
        case .smartZoom: Gestures.smartZoom()
        case .spotlight: HotKeyPoster.post(.spotlight)
        case .notificationCenter: HotKeyPoster.post(.notificationCenter)
        case .appSwitcher: HotKeyPoster.post(.appSwitcher)
        case .keyboardShortcut:
            if let s = shortcut { HotKeyPoster.postKey(s.keyCode, flags: s.modifiers) }
        }
    }

    /// Posts a native mouse click of the given CG button number.
    static func click(button: Int, at location: CGPoint) {
        if HotKeyPoster.dryRun { Log.info("DRYRUN click button=\(button)"); return }
        let cgButton = unsafeBitCast(UInt32(button), to: CGMouseButton.self)
        let types: [CGEventType] = button == 0 ? [.leftMouseDown, .leftMouseUp]
            : button == 1 ? [.rightMouseDown, .rightMouseUp] : [.otherMouseDown, .otherMouseUp]
        for type in types {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) else { continue }
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: HotKeyPoster.eventTag)
            e.post(tap: .cgSessionEventTap)
        }
    }
}
