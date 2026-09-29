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
        case .passThrough: return "Normal click (no change)"
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

    /// One-line explanation shown under the picker.
    var detail: String {
        switch self {
        case .none: return "Ignores the press completely. Apps never see it."
        case .passThrough: return "Sends this button's normal click, so it keeps its usual job."
        case .middleClick: return "Acts like pressing the scroll wheel, for example to open a link in a new tab."
        case .back: return "Goes back, like ⌘[ in browsers and Finder."
        case .forward: return "Goes forward, like ⌘] in browsers and Finder."
        case .missionControl: return "Shows all your open windows and Desktops."
        case .appExpose: return "Shows every window of the app you're using."
        case .showDesktop: return "Moves windows aside so you can see the desktop."
        case .launchpad: return "Opens the grid of all your apps."
        case .moveLeftSpace: return "Switches to the Desktop on the left."
        case .moveRightSpace: return "Switches to the Desktop on the right."
        case .lookUp: return "Looks up the word under the pointer."
        case .smartZoom: return "Zooms in on what's under the pointer, like a two-finger double-tap on a trackpad."
        case .spotlight: return "Opens Spotlight search."
        case .notificationCenter: return "Opens Notification Center."
        case .appSwitcher: return "Shows the app switcher, like pressing ⌘⇥."
        case .keyboardShortcut: return "Presses a key combination you choose. Record it in the box below."
        }
    }

    /// Completes "Click to …" in plain words, for the summary in the Guide tab.
    func phrase(_ shortcut: KeyShortcut?) -> String {
        switch self {
        case .none: return "do nothing"
        case .passThrough: return "click normally"
        case .middleClick: return "middle-click"
        case .back: return "go back"
        case .forward: return "go forward"
        case .missionControl: return "open Mission Control"
        case .appExpose: return "show the current app's windows"
        case .showDesktop: return "show the desktop"
        case .launchpad: return "open Launchpad"
        case .moveLeftSpace: return "move one Desktop left"
        case .moveRightSpace: return "move one Desktop right"
        case .lookUp: return "look up the word under the pointer"
        case .smartZoom: return "smart zoom"
        case .spotlight: return "open Spotlight"
        case .notificationCenter: return "open Notification Center"
        case .appSwitcher: return "show the app switcher"
        case .keyboardShortcut: return shortcut.map { "press \($0.display)" } ?? "press a shortcut (none recorded yet)"
        }
    }

    /// Menu order, grouped so related actions sit together.
    static let groups: [[ButtonAction]] = [
        [.passThrough, .none, .middleClick, .back, .forward],
        [.missionControl, .appExpose, .showDesktop, .launchpad, .moveLeftSpace, .moveRightSpace],
        [.lookUp, .smartZoom, .spotlight, .notificationCenter, .appSwitcher],
        [.keyboardShortcut],
    ]
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

    var detail: String {
        switch self {
        case .off: return "No drag gesture for this button."
        case .spacesAndMissionControl:
            return "Drag left or right to switch Desktops. Drag up for Mission Control, or down to see the current app's windows. The screen follows your hand, like a three-finger trackpad swipe."
        case .scrollAndNavigate:
            return "Drag in any direction to scroll, like dragging two fingers on a trackpad. Let go while still moving and the page keeps gliding."
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

    var detail: String {
        switch self {
        case .off: return "Scrolling while holding this button works normally."
        case .zoom: return "Scroll up to zoom in and down to zoom out, like pinching on a trackpad. Works wherever pinch-to-zoom does, such as browsers, Maps and Preview."
        case .rotate: return "Rotates photos and maps, like twisting two fingers on a trackpad."
        case .switchSpaces: return "Each notch moves one Desktop over: scroll down to go right, up to go left."
        case .swiftScroll: return "Each notch scrolls much farther, to get through long pages quickly."
        case .preciseScroll: return "Each notch scrolls a small, even step, for careful positioning."
        case .horizontalScroll: return "The wheel scrolls sideways instead of up and down."
        case .appSwitcher: return "Opens the app switcher. Keep scrolling to pick an app, then let go of the button to switch to it."
        }
    }

    /// Completes "Hold and scroll to …" for the summary in the Guide tab.
    var phrase: String {
        switch self {
        case .off: return "scroll normally"
        case .zoom: return "zoom in or out"
        case .rotate: return "rotate"
        case .switchSpaces: return "switch Desktops"
        case .swiftScroll: return "scroll fast"
        case .preciseScroll: return "scroll in small steps"
        case .horizontalScroll: return "scroll sideways"
        case .appSwitcher: return "switch apps"
        }
    }
}

enum Smoothing: String, Codable, CaseIterable, Identifiable {
    case off, regular, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .off: return "Each notch jumps straight to its new position, like a standard mouse."
        case .regular: return "Each notch glides briefly, then stops cleanly. Pages don't bounce at their ends."
        case .high: return "A longer, trackpad-like glide that coasts to a stop. Pages can bounce at their ends, just like with a trackpad."
        }
    }
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

/// Defaults mirror Mac Mouse Fix's out-of-the-box scrolling: High smoothness (its trackpad-simulation
/// mode), Medium speed. Direction is left as macOS delivers it.
struct ScrollConfig: Codable, Equatable {
    var enabled = true
    var smoothing: Smoothing = .high
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
        smoothing = try c.decodeIfPresent(Smoothing.self, forKey: .smoothing) ?? .high
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

    /// Short location, for people who don't know the numbering.
    static func location(_ b: Int) -> String? {
        switch b {
        case 2: return "press the scroll wheel"
        case 3: return "usually the rear side button"
        case 4: return "usually the front side button"
        default: return nil
        }
    }

    /// Where to find the button on a typical mouse.
    static func whereToFind(_ b: Int) -> String {
        switch b {
        case 2: return "The middle button is pressing down on the scroll wheel."
        case 3: return "Button 4 is usually the rear side button, next to your thumb. Most mice use it for Back."
        case 4: return "Button 5 is usually the front side button, next to your thumb. Most mice use it for Forward."
        default: return "Button \(b + 1) is an extra button found on some gaming and productivity mice. If your mouse doesn't have one, you can ignore it."
        }
    }
}

extension ButtonConfig {
    /// What this button does, in plain sentences, for the summary in the Guide tab.
    var summaryLines: [String] {
        var lines: [String] = []
        if click == .none { lines.append("A plain click does nothing") }
        else if click != .passThrough { lines.append("Click to \(click.phrase(clickShortcut))") }
        if doubleClick != .none { lines.append("Double-click to \(doubleClick.phrase(doubleClickShortcut))") }
        if hold != .none { lines.append("Hold to \(hold.phrase(holdShortcut))") }
        switch drag {
        case .off: break
        case .spacesAndMissionControl: lines.append("Hold and drag sideways to switch Desktops, up for Mission Control, down for App Exposé")
        case .scrollAndNavigate: lines.append("Hold and drag to scroll, like two fingers on a trackpad")
        }
        if scroll != .off { lines.append("Hold and scroll to \(scroll.phrase)") }
        return lines
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
        // One-time migration: scrolling defaults changed to Mac Mouse Fix's stock values; other settings are kept.
        if !UserDefaults.standard.bool(forKey: "migratedScrollDefaults.v3") {
            config.scroll = ScrollConfig()
            UserDefaults.standard.set(true, forKey: "migratedScrollDefaults.v3")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
