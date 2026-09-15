import Foundation
import Combine

// MARK: - Enumerations

enum ButtonAction: String, Codable, CaseIterable, Identifiable {
    case none, passThrough, middleClick, back, forward
    case missionControl, appExpose, showDesktop, launchpad, moveLeftSpace, moveRightSpace
    case lookUp, smartZoom, spotlight, notificationCenter, appSwitcher, keyboardShortcut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Nothing"
        case .passThrough: return "Pass through (native click)"
        case .middleClick: return "Middle Click"
        case .back: return "Back"
        case .forward: return "Forward"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad / Apps"
        case .moveLeftSpace: return "Move left a Space"
        case .moveRightSpace: return "Move right a Space"
        case .lookUp: return "Look Up"
        case .smartZoom: return "Smart Zoom"
        case .spotlight: return "Spotlight"
        case .notificationCenter: return "Notification Center"
        case .appSwitcher: return "App Switcher"
        case .keyboardShortcut: return "Keyboard Shortcut…"
        }
    }
}

enum DragEffect: String, Codable, CaseIterable, Identifiable {
    case off, spacesAndMissionControl, scrollAndNavigate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .spacesAndMissionControl: return "Spaces & Mission Control"
        case .scrollAndNavigate: return "Scroll & Navigate"
        }
    }
}

enum ScrollEffect: String, Codable, CaseIterable, Identifiable {
    case off, zoom, rotate, switchSpaces, swiftScroll, preciseScroll, horizontalScroll, appSwitcher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .zoom: return "Zoom in or out"
        case .rotate: return "Rotate"
        case .switchSpaces: return "Switch Spaces"
        case .swiftScroll: return "Swift scroll"
        case .preciseScroll: return "Precise scroll"
        case .horizontalScroll: return "Horizontal scroll"
        case .appSwitcher: return "App Switcher"
        }
    }
}

enum Smoothing: String, Codable, CaseIterable, Identifiable {
    case off, regular, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var timeConstant: Double { self == .high ? 0.12 : 0.06 }
}

enum ScrollSpeed: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var pixelsPerNotch: Double { switch self { case .low: return 32; case .medium: return 52; case .high: return 84 } }
}

struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64      // CGEventFlags raw value
    var display: String
}

struct ButtonConfig: Codable, Equatable {
    var click: ButtonAction = .passThrough
    var doubleClick: ButtonAction = .none
    var hold: ButtonAction = .none
    var clickShortcut: KeyShortcut? = nil
    var doubleClickShortcut: KeyShortcut? = nil
    var holdShortcut: KeyShortcut? = nil
    var drag: DragEffect = .off
    var scroll: ScrollEffect = .off

    /// True when the app should take ownership of this button at all ("Pass through" alone leaves it native).
    var isCaptured: Bool {
        click != .passThrough || doubleClick != .none || hold != .none || drag != .off || scroll != .off
    }

    init(click: ButtonAction = .passThrough, doubleClick: ButtonAction = .none, hold: ButtonAction = .none,
         drag: DragEffect = .off, scroll: ScrollEffect = .off) {
        self.click = click; self.doubleClick = doubleClick; self.hold = hold; self.drag = drag; self.scroll = scroll
    }

    // Tolerant decoding: new fields fall back to defaults instead of discarding the whole config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        click = try c.decodeIfPresent(ButtonAction.self, forKey: .click) ?? .passThrough
        doubleClick = try c.decodeIfPresent(ButtonAction.self, forKey: .doubleClick) ?? .none
        hold = try c.decodeIfPresent(ButtonAction.self, forKey: .hold) ?? .none
        clickShortcut = try c.decodeIfPresent(KeyShortcut.self, forKey: .clickShortcut)
        doubleClickShortcut = try c.decodeIfPresent(KeyShortcut.self, forKey: .doubleClickShortcut)
        holdShortcut = try c.decodeIfPresent(KeyShortcut.self, forKey: .holdShortcut)
        drag = try c.decodeIfPresent(DragEffect.self, forKey: .drag) ?? .off
        scroll = try c.decodeIfPresent(ScrollEffect.self, forKey: .scroll) ?? .off
    }
}

struct ScrollConfig: Codable, Equatable {
    var enabled = true
    var smoothing: Smoothing = .regular
    var speed: ScrollSpeed = .medium
    var reverse = false
    var modHorizontal = true   // Shift
    var modPrecise = true      // Option
    var modSwift = true        // Control
    var modZoom = true         // Command

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        smoothing = try c.decodeIfPresent(Smoothing.self, forKey: .smoothing) ?? .regular
        speed = try c.decodeIfPresent(ScrollSpeed.self, forKey: .speed) ?? .medium
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? false
        modHorizontal = try c.decodeIfPresent(Bool.self, forKey: .modHorizontal) ?? true
        modPrecise = try c.decodeIfPresent(Bool.self, forKey: .modPrecise) ?? true
        modSwift = try c.decodeIfPresent(Bool.self, forKey: .modSwift) ?? true
        modZoom = try c.decodeIfPresent(Bool.self, forKey: .modZoom) ?? true
    }
}

struct PointerConfig: Codable, Equatable {
    var useSystemSettings = true
    var sensitivity = 1.0      // 0.25 … 3
    var acceleration = 0.6875  // 0 = linear (off) … 3

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useSystemSettings = try c.decodeIfPresent(Bool.self, forKey: .useSystemSettings) ?? true
        sensitivity = min(3, max(0.25, try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.0))
        acceleration = min(3, max(0, try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? 0.6875))
    }
}

struct Config: Codable, Equatable {
    var enabled = true
    var buttons: [String: ButtonConfig] = [:]   // key: CG button number ("2" = middle, "3" = button 4 …)
    var freezePointerDuringDrag = false
    var spacesNaturalDirection = true
    var spacesDragScale = 1.0                    // 1.0 = Spaces follow the pointer exactly
    var dragScrollMomentum = true
    var dragScrollInvert = false
    var scroll = ScrollConfig()
    var pointer = PointerConfig()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        buttons = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .buttons) ?? [:]
        freezePointerDuringDrag = try c.decodeIfPresent(Bool.self, forKey: .freezePointerDuringDrag) ?? false
        spacesNaturalDirection = try c.decodeIfPresent(Bool.self, forKey: .spacesNaturalDirection) ?? true
        spacesDragScale = min(2, max(0.5, try c.decodeIfPresent(Double.self, forKey: .spacesDragScale) ?? 1.0))
        dragScrollMomentum = try c.decodeIfPresent(Bool.self, forKey: .dragScrollMomentum) ?? true
        dragScrollInvert = try c.decodeIfPresent(Bool.self, forKey: .dragScrollInvert) ?? false
        scroll = try c.decodeIfPresent(ScrollConfig.self, forKey: .scroll) ?? ScrollConfig()
        pointer = try c.decodeIfPresent(PointerConfig.self, forKey: .pointer) ?? PointerConfig()
    }

    /// Mirrors the user's Mac Mouse Fix setup: Button 4 click = Back, Button 4 drag = Spaces,
    /// Button 5 drag = Scroll; middle button stays native.
    static var defaults: Config {
        var c = Config()
        c.buttons["2"] = ButtonConfig(click: .passThrough)
        c.buttons["3"] = ButtonConfig(click: .back, drag: .spacesAndMissionControl, scroll: .switchSpaces)
        c.buttons["4"] = ButtonConfig(click: .none, drag: .scrollAndNavigate, scroll: .zoom)
        return c
    }

    func button(_ n: Int) -> ButtonConfig { buttons[String(n)] ?? ButtonConfig() }
    mutating func setButton(_ n: Int, _ cfg: ButtonConfig) { buttons[String(n)] = cfg }
}

enum MouseButton {
    static let middle = 2, button4 = 3, button5 = 4
    static let configurable = [2, 3, 4, 5, 6, 7]
    static func name(_ b: Int) -> String {
        switch b {
        case 2: return "Middle Button"
        default: return "Button \(b + 1)"
        }
    }
}

// MARK: - Store

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "config.v2"
    @Published var config: Config { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            do { config = try JSONDecoder().decode(Config.self, from: data) }
            catch { Log.info("config decode failed (\(error)), using defaults"); config = .defaults }
        } else {
            config = .defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
