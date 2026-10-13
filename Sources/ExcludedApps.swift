import SwiftUI
import UniformTypeIdentifiers

extension ExcludedApp {
    init?(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier ?? app.executableURL?.path else { return nil }
        self.init(id: id, name: app.localizedName ?? (id as NSString).lastPathComponent)
    }

    init?(bundleURL url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier ?? bundle.executableURL?.path else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        self.init(id: id, name: name)
    }

    var icon: NSImage {
        let ws = NSWorkspace.shared
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, let icon = running.icon { return icon }
        if let url = ws.urlForApplication(withBundleIdentifier: id) { return ws.icon(forFile: url.path) }
        if id.hasPrefix("/"), FileManager.default.fileExists(atPath: id) { return ws.icon(forFile: id) }
        return ws.icon(for: .application)
    }

    /// The icon drawn at menu size; menus show images at their own size, and app icons are 1024 pt.
    var menuIcon: NSImage {
        let full = icon
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in full.draw(in: rect); return true }
    }
}

extension NSRunningApplication {
    /// The key apps are listed under in the Scrolling tab: bundle identifier, or executable path without one.
    var excludedAppID: String? { bundleIdentifier ?? executableURL?.path }
}

/// Scrolling tab section: apps in which smooth scrolling is switched off while they're in front.
struct ExcludedAppsSection: View {
    @ObservedObject var store: SettingsStore
    @State private var running: [ExcludedApp] = []

    private var list: [ExcludedApp] { store.config.scroll.excludedApps }
    private var candidates: [ExcludedApp] { running.filter { !store.config.scroll.excludes($0.id) } }

    var body: some View {
        Section {
            if list.isEmpty {
                Hint("No apps yet, so smooth scrolling works everywhere.")
            }
            ForEach(list) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                    Button { remove(app) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Use smooth scrolling in \(app.name) again.")
                }
            }
            HStack {
                Spacer()
                Menu("Add App") {
                    Button("Choose from Applications…") { choose() }
                    if !candidates.isEmpty {
                        Section("Open Now") {
                            ForEach(candidates) { app in
                                Button { add([app]) } label: {
                                    Label { Text(app.name) } icon: { Image(nsImage: app.menuIcon) }
                                }
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                .fixedSize()
                .help("Pick an app that's open now, or any app in your Applications folder.")
            }
        } header: {
            Text("Apps without smooth scrolling")
        } footer: {
            Hint(store.config.scroll.enabled
                 ? "While one of these apps is in front, MouseDragFix leaves the wheel alone, so it scrolls exactly as macOS does it and the keys above do nothing extra. Handy for games. Hold and scroll button effects still work. You can also switch this from the menu bar icon while using the app."
                 : "Turn on smooth scrolling above to use this.")
        }
        .onReceive(NSWorkspace.shared.publisher(for: \.runningApplications)) { apps in
            var seen = Set<String>()
            running = apps
                .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
                .compactMap(ExcludedApp.init)
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func add(_ apps: [ExcludedApp]) {
        for app in apps where !store.config.scroll.excludes(app.id) {
            store.config.scroll.excludedApps.append(app)
        }
    }

    private func remove(_ app: ExcludedApp) {
        store.config.scroll.excludedApps.removeAll { $0.id == app.id }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose the apps that should scroll without smoothing."
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap { ExcludedApp(bundleURL: $0) })
    }
}
