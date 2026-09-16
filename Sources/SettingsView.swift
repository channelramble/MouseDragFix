import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var status = AppStatus.shared

    var body: some View {
        TabView {
            GeneralTab(store: store, status: status).tabItem { Label("General", systemImage: "gearshape") }
            ButtonsTab(store: store).tabItem { Label("Buttons", systemImage: "computermouse") }
            ScrollingTab(store: store).tabItem { Label("Scrolling", systemImage: "arrow.up.and.down") }
            PointerTab(store: store).tabItem { Label("Pointer", systemImage: "cursorarrow") }
        }
        .frame(minWidth: 640, minHeight: 580)
    }
}

/// Live status shared with the UI (permission, tap state).
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    @Published var accessibilityTrusted = false
    @Published var tapRunning = false
    @Published var tapError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: AppStatus

    var body: some View {
        Form {
            Section {
                Toggle("Enable MouseDragFix", isOn: $store.config.enabled)
                Toggle("Launch at login", isOn: Binding(get: { status.launchAtLogin }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { Log.info("launch at login: \(error)") }
                    status.launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
                HStack {
                    Image(systemName: status.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.accessibilityTrusted ? .green : .orange)
                    Text(status.accessibilityTrusted
                         ? (status.tapRunning ? "Accessibility granted, listening for mouse input" : (status.tapError ?? "Not running"))
                         : "Accessibility permission required")
                    Spacer()
                    if !status.accessibilityTrusted {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
            Section("Click and Drag") {
                Toggle("Freeze pointer during drag gestures", isOn: $store.config.freezePointerDuringDrag)
                Toggle("Natural direction for Spaces (drag left reveals the Space on the right)", isOn: $store.config.spacesNaturalDirection)
                HStack {
                    Text("Spaces drag scale")
                    Slider(value: $store.config.spacesDragScale, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2f×", store.config.spacesDragScale)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Text("1.00× makes Spaces follow the pointer exactly, like a three-finger swipe.").font(.caption).foregroundStyle(.secondary)
                Toggle("Momentum for Scroll & Navigate drags", isOn: $store.config.dragScrollMomentum)
                Toggle("Invert Scroll & Navigate direction", isOn: $store.config.dragScrollInvert)
            }
            Section {
                Button("Reset all settings to defaults") { store.config = .defaults }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Buttons

struct ButtonsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selected = MouseButton.button4

    var body: some View {
        VStack(spacing: 0) {
            Picker("Button", selection: $selected) {
                ForEach(MouseButton.configurable, id: \.self) { Text(MouseButton.name($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            Form {
                Section("Click") {
                    actionRow("Click", \.click, \.clickShortcut)
                    actionRow("Double Click", \.doubleClick, \.doubleClickShortcut)
                    actionRow("Hold", \.hold, \.holdShortcut)
                    Text("Assigning a Double Click action delays single clicks slightly.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Click and Drag") {
                    Picker("Hold and drag", selection: bind(\.drag)) {
                        ForEach(DragEffect.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Click and Scroll") {
                    Picker("Hold and scroll", selection: bind(\.scroll)) {
                        ForEach(ScrollEffect.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func actionRow(_ title: String, _ kp: WritableKeyPath<ButtonConfig, ButtonAction>,
                           _ skp: WritableKeyPath<ButtonConfig, KeyShortcut?>) -> some View {
        Picker(title, selection: bind(kp)) {
            ForEach(ButtonAction.allCases) { Text($0.title).tag($0) }
        }
        if store.config.button(selected)[keyPath: kp] == .keyboardShortcut {
            HStack { Spacer(); ShortcutRecorder(shortcut: bind(skp)).fixedSize() }
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
                Toggle("Enhance scroll wheel scrolling", isOn: $store.config.scroll.enabled)
                Text("Trackpad and Magic Mouse scrolling is never changed.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Scrolling") {
                Picker("Smoothness", selection: $store.config.scroll.smoothing) {
                    ForEach(Smoothing.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Speed", selection: $store.config.scroll.speed) {
                    ForEach(ScrollSpeed.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("Reverse direction", isOn: $store.config.scroll.reverse)
            }
            Section("Modifier keys") {
                Toggle("⇧ Shift: scroll horizontally", isOn: $store.config.scroll.modHorizontal)
                Toggle("⌥ Option: precise scroll", isOn: $store.config.scroll.modPrecise)
                Toggle("⌃ Control: swift scroll", isOn: $store.config.scroll.modSwift)
                Toggle("⌘ Command: zoom in or out", isOn: $store.config.scroll.modZoom)
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
        HStack(spacing: 2) {
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

    var body: some View {
        Form {
            Section {
                Toggle("Use macOS pointer settings", isOn: $store.config.pointer.useSystemSettings)
                Text("When off, speed and acceleration below are applied to every connected mouse and restored when the app quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pointer") {
                HStack {
                    Text("Speed")
                    Slider(value: $store.config.pointer.sensitivity, in: 0.25...3.0, step: 0.05)
                    NumberField(value: $store.config.pointer.sensitivity, range: 0.25...3.0, suffix: "×")
                }
                HStack {
                    Text("Acceleration")
                    Slider(value: $store.config.pointer.acceleration, in: 0...3.0, step: 0.0625)
                    NumberField(value: $store.config.pointer.acceleration, range: 0...3.0, suffix: "")
                }
                Text("Acceleration \"Off\" gives a linear, 1:1 pointer. macOS default is 0.6875.").font(.caption).foregroundStyle(.secondary)
            }
            .disabled(store.config.pointer.useSystemSettings)
        }
        .formStyle(.grouped)
    }
}
