import SwiftUI
import ServiceManagement

// MARK: - Shared state

enum SettingsTab: Hashable { case guide, general, buttons, scrolling, pointer }

/// Live status shared with the UI (permission, tap state, conflicts, which tab to show).
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    @Published var accessibilityTrusted = false
    @Published var tapRunning = false
    @Published var tapError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Mac Mouse Fix is running too, so both apps would react to the same input.
    @Published var macMouseFixRunning = false
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var status = AppStatus.shared

    var body: some View {
        TabView(selection: $status.selectedTab) {
            GuideTab(store: store, status: status)
                .tabItem { Label("Guide", systemImage: "questionmark.circle") }
                .tag(SettingsTab.guide)
            GeneralTab(store: store, status: status)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ButtonsTab(store: store)
                .tabItem { Label("Buttons", systemImage: "computermouse") }
                .tag(SettingsTab.buttons)
            ScrollingTab(store: store)
                .tabItem { Label("Scrolling", systemImage: "arrow.up.and.down") }
                .tag(SettingsTab.scrolling)
            PointerTab(store: store)
                .tabItem { Label("Pointer", systemImage: "cursorarrow") }
                .tag(SettingsTab.pointer)
        }
        .frame(minWidth: 640, minHeight: 580)
    }
}

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Building blocks

/// Secondary explanatory text under a control.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A control's title with an explanation underneath, used as the label of toggles and pickers.
struct Titled: View {
    let title: String
    let detail: String?
    init(_ title: String, _ detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail { Hint(detail) }
        }
    }
}

/// A highlighted note with an icon, for status, warnings and tips.
struct Callout: View {
    enum Kind { case ok, info, tip, warning }
    let kind: Kind
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch kind {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .ok: return .green
        case .info: return .blue
        case .tip: return .yellow
        case .warning: return .orange
        }
    }
}

/// An icon, a short title and a sentence of explanation, for tips and troubleshooting.
struct TipRow: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Hint(text)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// Accessibility permission state with step-by-step help. MouseDragFix can't see the mouse without it.
struct PermissionStatus: View {
    @ObservedObject var status: AppStatus

    var body: some View {
        if status.accessibilityTrusted {
            if status.tapRunning {
                Callout(kind: .ok, title: "Ready to go",
                        message: "Accessibility access is on, so MouseDragFix can see your mouse.")
            } else {
                Callout(kind: .warning, title: "Not running",
                        message: status.tapError ?? "MouseDragFix couldn't start listening to the mouse. Quit it from the menu bar and open it again.")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Callout(kind: .warning, title: "Accessibility access needed",
                        message: "macOS only lets an app read and change mouse input after you allow it. MouseDragFix doesn't collect or send anything.")
                VStack(alignment: .leading, spacing: 4) {
                    Text("1.  Click Open System Settings below.")
                    Text("2.  Turn on the switch next to MouseDragFix.")
                    Text("3.  Come back here. MouseDragFix starts by itself within a couple of seconds.")
                }
                .font(.callout)
                HStack {
                    Button("Open System Settings") { openAccessibilitySettings() }
                        .help("Opens Privacy & Security › Accessibility.")
                    Spacer()
                }
                Hint("Already switched on but still not working? That can happen after an update. Select MouseDragFix in the list, click the − button to remove it, then open MouseDragFix again and allow it once more.")
            }
        }
    }
}

// MARK: - Guide

struct GuideTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: AppStatus
    @State private var spaces: Int?

    private let tips: [(icon: String, title: String, text: String)] = [
        ("menubar.rectangle", "It lives in the menu bar",
         "Click the mouse icon at the top right of your screen to pause MouseDragFix or reopen this window. Closing this window keeps it running."),
        ("hand.point.up.left", "Only what you set up changes",
         "Buttons, scrolling and pointer options you leave alone work exactly as they did before."),
        ("computermouse", "Which button is which?",
         "Button 4 is usually the rear side button and Button 5 the front one. The middle button is pressing the scroll wheel."),
        ("timer", "Hold versus drag",
         "Hold means pressing and keeping still for about a third of a second. Start moving sooner and it becomes a drag instead."),
        ("rectangle.split.3x1", "Desktops, also called Spaces",
         "The extra screens you add in Mission Control. You need at least two to switch between them."),
        ("pause.circle", "Pause anytime",
         "Turn off Enable MouseDragFix in the General tab or the menu bar, and your mouse works exactly as it would without it."),
    ]

    private let fixes: [(title: String, text: String)] = [
        ("Nothing happens at all",
         "Check Step 1 above. After an update, macOS sometimes needs MouseDragFix removed from the Accessibility list with the − button and allowed again."),
        ("A button stopped doing its usual job",
         "Its Click is probably set to Nothing. In the Buttons tab, set it to Normal click (no change). Button 5 is often the Forward button."),
        ("A button does two things at once",
         "Another mouse app, such as Mac Mouse Fix or Logi Options+, is handling the same button. Turn that button off in the other app, or quit it."),
        ("Switching Desktops does nothing",
         "You need at least two Desktops. Open Mission Control and click + at the top right to add one."),
        ("Zoom doesn't work in an app",
         "Zooming acts like a trackpad pinch, so it only works in apps that support pinch-to-zoom."),
        ("Pages bounce when they reach the end",
         "That's the trackpad feel of High smoothness. Choose Regular in the Scrolling tab for a clean stop."),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome to MouseDragFix").font(.title2).fontWeight(.semibold)
                        Text("Gives any mouse trackpad-style gestures, smooth scrolling and extra button actions. Here's how to get going.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section("Step 1: Allow access") {
                PermissionStatus(status: status)
            }

            Section {
                ForEach(MouseButton.configurable.filter { store.config.button($0).isCaptured }, id: \.self) { b in
                    summaryRow(icon: "computermouse", title: MouseButton.name(b),
                               subtitle: MouseButton.location(b), lines: store.config.button(b).summaryLines)
                }
                summaryRow(icon: "arrow.up.and.down", title: "Scroll wheel", subtitle: nil, lines: scrollLines)
                summaryRow(icon: "cursorarrow", title: "Pointer", subtitle: nil, lines: [pointerLine])
                Hint("Every other button works normally.")
            } header: {
                Text("Step 2: Try it out")
            } footer: {
                Hint("This is how your mouse is set up right now. Change any of it in the Buttons, Scrolling and Pointer tabs.")
            }

            Section("Good to know") {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, t in
                    TipRow(icon: t.icon, title: t.title, text: t.text)
                }
            }

            Section("If something isn't working") {
                if status.macMouseFixRunning {
                    Callout(kind: .warning, title: "Mac Mouse Fix is running right now",
                            message: "Both apps will react to the same buttons and scrolling. Quit Mac Mouse Fix, or turn off its Buttons and Scrolling switches.")
                }
                if let spaces, spaces < 2 {
                    Callout(kind: .tip, title: "You have only one Desktop",
                            message: "Dragging sideways to switch Desktops needs at least two. Open Mission Control and click + at the top right to add one.")
                }
                ForEach(Array(fixes.enumerated()), id: \.offset) { _, f in
                    TipRow(icon: "wrench.and.screwdriver", title: f.title, text: f.text)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { spaces = DockSwipe.shared.maxSpacesPerDisplay() }
    }

    private func summaryRow(icon: String, title: String, subtitle: String?, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(lines, id: \.self) { line in
                    Text("•  " + line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var scrollLines: [String] {
        let s = store.config.scroll
        guard s.enabled else { return ["Works normally (smooth scrolling is off)"] }
        var lines = [s.smoothing == .off
                     ? "Standard steps (smoothness off), \(s.speed.title.lowercased()) speed"
                     : "Scrolls smoothly: \(s.smoothing.title) smoothness, \(s.speed.title) speed"]
        var mods: [String] = []
        if s.modHorizontal { mods.append("⇧ Shift to scroll sideways") }
        if s.modPrecise { mods.append("⌥ Option for small steps") }
        if s.modSwift { mods.append("⌃ Control for big jumps") }
        if s.modZoom { mods.append("⌘ Command to zoom") }
        if !mods.isEmpty { lines.append("While scrolling, hold " + mods.joined(separator: ", ")) }
        return lines
    }

    private var pointerLine: String {
        let p = store.config.pointer
        if p.useSystemSettings { return "Uses your macOS pointer settings" }
        let accel = p.acceleration == 0 ? "acceleration off" : String(format: "acceleration %.2f", p.acceleration)
        return String(format: "Custom: speed %.2f×, ", p.sensitivity) + accel
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: AppStatus
    @State private var confirmReset = false
    @State private var spaces: Int?

    var body: some View {
        Form {
            Section {
                PermissionStatus(status: status)
            }

            Section {
                Toggle(isOn: $store.config.enabled) {
                    Titled("Enable MouseDragFix", store.config.enabled
                           ? "On: your buttons, scrolling and pointer work as set up in these tabs."
                           : "Paused: your mouse works exactly as it would without MouseDragFix. Turn this back on to resume.")
                }
                .help("Pause or resume MouseDragFix without quitting it.")
                Toggle(isOn: Binding(get: { status.launchAtLogin }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { Log.info("launch at login: \(error)") }
                    status.launchAtLogin = SMAppService.mainApp.status == .enabled
                })) {
                    Titled("Launch at login", "Starts MouseDragFix when you log in, so your mouse is always set up.")
                }
                .help("Start MouseDragFix automatically when you log in to your Mac.")
            }

            if status.macMouseFixRunning {
                Section {
                    Callout(kind: .warning, title: "Mac Mouse Fix is also running",
                            message: "Both apps will react to the same buttons and scrolling. Quit Mac Mouse Fix, or turn off its Buttons and Scrolling switches.")
                }
            }

            Section {
                Toggle(isOn: $store.config.freezePointerDuringDrag) {
                    Titled("Freeze pointer during drag gestures",
                           "Keeps the pointer still while you hold and drag, so it ends up where you started.")
                }
                Toggle(isOn: $store.config.spacesNaturalDirection) {
                    Titled("Natural direction for Desktops",
                           store.config.spacesNaturalDirection
                           ? "Dragging left reveals the Desktop on the right, like a three-finger swipe."
                           : "Dragging left goes to the Desktop on the left.")
                }
                HStack {
                    Titled("Desktop drag distance",
                           "1.00× makes the screen follow the pointer exactly. Lower needs a longer drag to switch; higher a shorter one.")
                    Slider(value: $store.config.spacesDragScale, in: 0.5...2.0, step: 0.05)
                        .frame(minWidth: 140)
                        .help("How far you drag to move one Desktop.")
                    Text(String(format: "%.2f×", store.config.spacesDragScale)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                if let spaces, spaces < 2 {
                    Callout(kind: .tip, title: "You have only one Desktop",
                            message: "Dragging sideways needs at least two. Open Mission Control and click + at the top right to add one.")
                }
                Toggle(isOn: $store.config.dragScrollMomentum) {
                    Titled("Momentum for Scroll & Navigate drags",
                           "Let go while still moving and the page keeps gliding, then slows to a stop.")
                }
                Toggle(isOn: $store.config.dragScrollInvert) {
                    Titled("Invert Scroll & Navigate direction",
                           store.config.dragScrollInvert
                           ? "The page moves the opposite way to your hand."
                           : "The page moves with your hand, as if you were pushing paper around.")
                }
            } header: {
                Text("Click and Drag")
            } footer: {
                Hint("These apply to every button with a drag effect. Choose which buttons use which effect in the Buttons tab.")
            }

            Section {
                HStack {
                    Titled("Reset all settings", "Puts every button, scrolling and pointer setting back to how MouseDragFix came.")
                    Spacer()
                    Button("Reset…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { spaces = DockSwipe.shared.maxSpacesPerDisplay() }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.config = .defaults }
        } message: {
            Text("Every button, scrolling and pointer setting goes back to its default. This can't be undone.")
        }
    }
}

// MARK: - Buttons

struct ButtonsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selected = MouseButton.button4

    private enum Trigger { case click, doubleClick, hold }
    private var cfg: ButtonConfig { store.config.button(selected) }
    private var name: String { MouseButton.name(selected) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a mouse button, then choose what it does.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Button", selection: $selected) {
                    ForEach(MouseButton.configurable, id: \.self) { Text(MouseButton.name($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Choose which mouse button to set up.")
                Hint(MouseButton.whereToFind(selected))
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 2)

            Form {
                Section {
                    if cfg.isCaptured {
                        Callout(kind: .info, title: "\(name) is customized",
                                message: "MouseDragFix handles this button using the settings below.")
                    } else {
                        Callout(kind: .info, title: "\(name) works normally",
                                message: "MouseDragFix isn't changing this button. Choose an action below to customize it.")
                    }
                    if cfg.click == .none {
                        Callout(kind: .warning, title: "A plain click on \(name) does nothing",
                                message: "Set Click to Normal click (no change) if you want the button to keep its usual job.")
                    }
                }

                Section {
                    actionRow("Click", .click, \.click, \.clickShortcut)
                    actionRow("Double Click", .doubleClick, \.doubleClick, \.doubleClickShortcut)
                    actionRow("Hold", .hold, \.hold, \.holdShortcut)
                } header: {
                    Text("Click")
                } footer: {
                    Hint("Hold means pressing and keeping still for about a third of a second. Setting a Double Click action makes single clicks wait that long too, to tell the two apart.")
                }

                Section {
                    Picker(selection: bind(\.drag)) {
                        ForEach(DragEffect.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Titled("Hold and drag", cfg.drag.detail)
                    }
                    .help("What happens when you hold this button and move the mouse.")
                    if cfg.hold != .none && cfg.drag != .off {
                        Hint("This button also has a Hold action. Keep still to trigger Hold, or start moving right away to drag.")
                    }
                } header: {
                    Text("Click and Drag")
                } footer: {
                    Hint("Press and hold the button, then move the mouse. Fine-tune how drags feel in the General tab.")
                }

                Section {
                    Picker(selection: bind(\.scroll)) {
                        ForEach(ScrollEffect.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Titled("Hold and scroll", cfg.scroll.detail)
                    }
                    .help("What happens when you hold this button and turn the scroll wheel.")
                } header: {
                    Text("Click and Scroll")
                } footer: {
                    Hint("Press and hold the button, then turn the scroll wheel. Using the wheel this way won't also trigger the button's click.")
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func actionRow(_ title: String, _ trigger: Trigger, _ kp: WritableKeyPath<ButtonConfig, ButtonAction>,
                           _ skp: WritableKeyPath<ButtonConfig, KeyShortcut?>) -> some View {
        let action = cfg[keyPath: kp]
        Picker(selection: bind(kp)) {
            ForEach(Array(ButtonAction.groups.enumerated()), id: \.offset) { i, group in
                if i > 0 { Divider() }
                ForEach(group) { Text($0.title).tag($0) }
            }
        } label: {
            Titled(title, detail(for: action, trigger))
        }
        .help(help(for: trigger))
        if action == .keyboardShortcut {
            HStack {
                Hint(cfg[keyPath: skp] == nil
                     ? "Nothing recorded yet, so this does nothing. Click the box, then press the keys you want."
                     : "Click the box to record a different shortcut. Esc cancels.")
                Spacer()
                ShortcutRecorder(shortcut: bind(skp)).fixedSize()
            }
        }
    }

    private func detail(for action: ButtonAction, _ trigger: Trigger) -> String {
        guard action == .none else { return action.detail }
        switch trigger {
        case .click: return "Ignores the click completely. Apps never see it."
        case .doubleClick: return "No special action. A double-click counts as two clicks."
        case .hold: return "No special action when you hold the button."
        }
    }

    private func help(for trigger: Trigger) -> String {
        switch trigger {
        case .click: return "What a quick press and release of this button does."
        case .doubleClick: return "What two quick presses of this button do."
        case .hold: return "What pressing this button and keeping still does."
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<ButtonConfig, T>) -> Binding<T> {
        Binding(get: { store.config.button(selected)[keyPath: kp] },
                set: { v in var c = store.config.button(selected); c[keyPath: kp] = v; store.config.setButton(selected, c) })
    }
}

// MARK: - Scrolling

struct ScrollingTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.config.scroll.enabled) {
                    Titled("Smooth scrolling for mouse wheels",
                           "Makes a regular mouse wheel scroll smoothly, and turns on the key tricks below. Trackpads and Magic Mouse are never changed.")
                }
                .help("Turn off to leave mouse wheel scrolling exactly as macOS does it.")
            }

            Section {
                Picker(selection: $store.config.scroll.smoothing) {
                    ForEach(Smoothing.allCases) { Text($0.title).tag($0) }
                } label: {
                    Titled("Smoothness", store.config.scroll.smoothing.detail)
                }
                .pickerStyle(.segmented)
                Picker(selection: $store.config.scroll.speed) {
                    ForEach(ScrollSpeed.allCases) { Text($0.title).tag($0) }
                } label: {
                    Titled("Speed", "How far one notch scrolls. Spinning the wheel faster always goes farther.")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $store.config.scroll.reverse) {
                    Titled("Reverse direction", "Scrolls the other way. Turn this on if the wheel feels backwards.")
                }
            } header: {
                Text("Scrolling")
            } footer: {
                if !store.config.scroll.enabled {
                    Hint("Smooth scrolling is off, so the wheel works as macOS sets it. Smoothness and speed still apply to the Hold and scroll effects in the Buttons tab.")
                }
            }

            Section {
                Toggle(isOn: $store.config.scroll.modHorizontal) {
                    Titled("⇧ Shift: scroll sideways", "Handy for wide spreadsheets, timelines and code.")
                }
                Toggle(isOn: $store.config.scroll.modPrecise) {
                    Titled("⌥ Option: precise scroll", "Small, even steps for careful positioning.")
                }
                Toggle(isOn: $store.config.scroll.modSwift) {
                    Titled("⌃ Control: swift scroll", "Big jumps to get through long pages fast.")
                }
                Toggle(isOn: $store.config.scroll.modZoom) {
                    Titled("⌘ Command: zoom in or out",
                           "Works like a trackpad pinch in browsers, Maps, Preview and other apps that support pinch-to-zoom.")
                }
            } header: {
                Text("Hold a key while scrolling")
            } footer: {
                Hint(store.config.scroll.enabled
                     ? "Turn off any key you already use with the scroll wheel for something else."
                     : "Turn on smooth scrolling above to use these.")
            }
            .disabled(!store.config.scroll.enabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pointer

/// Editable number next to a slider: type a value, press Return or tab away to commit (clamped to range).
struct NumberField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {   // keeps the "×" on the number's baseline
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 58)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onAppear { text = format(value) }
                .onChange(of: value) { _, v in if !focused { text = format(v) } }
                .help(String(format: "Type a value from %.2f to %.2f, then press Return.", range.lowerBound, range.upperBound))
            Text(suffix).frame(width: 12, alignment: .leading)
        }
    }

    private func format(_ v: Double) -> String { String(format: "%.2f", v) }
    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if let v = Double(cleaned) { value = min(range.upperBound, max(range.lowerBound, v)) }
        text = format(value)
    }
}

struct PointerTab: View {
    @ObservedObject var store: SettingsStore

    private var useSystem: Bool { store.config.pointer.useSystemSettings }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.config.pointer.useSystemSettings) {
                    Titled("Use macOS pointer settings", useSystem
                           ? "Your mouse moves exactly as set in System Settings › Mouse. Turn this off to use the speed and acceleration below instead."
                           : "The speed and acceleration below apply to every connected mouse. Your macOS settings come back when you turn this on again or quit MouseDragFix.")
                }
                .help("Leave on to keep the pointer exactly as macOS sets it.")
            }

            Section {
                HStack {
                    Titled("Speed", "1.00× is normal. Higher moves the pointer farther for the same hand movement.")
                    Slider(value: $store.config.pointer.sensitivity, in: 0.25...3.0, step: 0.05)
                        .frame(minWidth: 140)
                    NumberField(value: $store.config.pointer.sensitivity, range: 0.25...3.0, suffix: "×")
                }
                HStack {
                    Titled("Acceleration", "How much the pointer speeds up when you move the mouse quickly. 0 turns it off for a steady 1:1 feel. macOS normally uses 0.69.")
                    Slider(value: $store.config.pointer.acceleration, in: 0...3.0, step: 0.0625)
                        .frame(minWidth: 140)
                    NumberField(value: $store.config.pointer.acceleration, range: 0...3.0, suffix: "")
                }
            } header: {
                Text("Pointer")
            } footer: {
                Hint(useSystem
                     ? "Turn off Use macOS pointer settings above to change these."
                     : "Drag a slider, or type a number and press Return. Trackpads aren't affected.")
            }
            .disabled(useSystem)
        }
        .formStyle(.grouped)
    }
}
