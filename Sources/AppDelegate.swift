import Cocoa
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let engine = GestureEngine()
    private let store = SettingsStore.shared
    private let status = AppStatus.shared
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var helperWatch: Timer?
    private var sigterm: DispatchSourceSignal?
    private var knownHelperPids: Set<pid_t> = []
    private var helperWatchPrimed = false

    private func checkMacMouseFixHelper() {
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier?.lowercased().contains("mac-mouse-fix") == true }
            .map(\.processIdentifier))
        if status.macMouseFixRunning != !pids.isEmpty { status.macMouseFixRunning = !pids.isEmpty }
        let newPids = pids.subtracting(knownHelperPids)
        knownHelperPids = pids
        guard helperWatchPrimed else { helperWatchPrimed = true; return }   // instances running before us are already behind our tap
        guard !newPids.isEmpty, engine.isRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            Log.info("Mac Mouse Fix (re)started (pids \(newPids.sorted())), re-inserting event tap")
            self.engine.stop(); self.engine.start(); self.status.tapRunning = self.engine.isRunning
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseDragFix")
            button.image?.isTemplate = true
            button.toolTip = "MouseDragFix: click to pause it or open Settings"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        checkPermissionAndStart(prompt: true)

        // Quit cleanly on SIGTERM (pkill, logout) so pointer settings and gestures are restored.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
        self.sigterm = sigterm

        PointerSpeed.shared.restoreLeftoversFromPreviousRun()
        // Apply pointer speed/acceleration whenever that part of the config changes.
        store.$config.map(\.pointer).removeDuplicates().sink { PointerSpeed.shared.apply($0) }.store(in: &cancellables)
        // Disabling mid-press must not leave a gesture, ⌘ key or frozen pointer behind.
        store.$config.map(\.enabled).removeDuplicates().sink { [weak self] on in if !on { self?.engine.cancelHold() } }.store(in: &cancellables)

        // Mac Mouse Fix's helper also taps mouse buttons at the HID level. It is relaunched by launchd
        // (no NSWorkspace launch notification), so watch its process ids and re-create our tap whenever a
        // new helper instance appears, keeping ours first in line.
        helperWatch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkMacMouseFixHelper() }
        checkMacMouseFixHelper()

        // First launch, or permission still missing: open on the Guide, which walks through both.
        let first = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        if first || !status.accessibilityTrusted { showWindow(.guide) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        PointerSpeed.shared.restore()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(status.accessibilityTrusted ? .general : .guide); return true
    }

    // MARK: Accessibility

    private func checkPermissionAndStart(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        status.accessibilityTrusted = AXIsProcessTrustedWithOptions(opts)
        if status.accessibilityTrusted {
            permissionTimer?.invalidate(); permissionTimer = nil
            engine.start()
            status.tapRunning = engine.isRunning
            status.tapError = engine.lastError
        } else if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.checkPermissionAndStart(prompt: false)
            }
        }
    }

    // MARK: Settings window

    @objc func showSettings() { showWindow(.general) }
    @objc func showGuide() { showWindow(.guide) }
    @objc private func allowAccessibility() { openAccessibilitySettings(); showWindow(.guide) }

    private func showWindow(_ tab: SettingsTab) {
        status.selectedTab = tab
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "MouseDragFix"
            let host = NSHostingView(rootView: SettingsView())
            host.autoresizingMask = [.width, .height]
            w.contentView = host
            w.contentMinSize = NSSize(width: 640, height: 580)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("SettingsWindow")
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let enabled = NSMenuItem(title: "Enable MouseDragFix", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self; enabled.state = store.config.enabled ? .on : .off
        enabled.toolTip = "Pause or resume MouseDragFix without quitting it."
        menu.addItem(enabled)

        let statusText: String
        if !status.accessibilityTrusted { statusText = "Needs Accessibility access to work" }
        else if !store.config.enabled { statusText = "Paused: your mouse works normally" }
        else if engine.isRunning { statusText = "Active: your mouse is customized" }
        else { statusText = engine.lastError ?? "Not running. Quit and open it again." }
        let s = NSMenuItem(title: statusText, action: nil, keyEquivalent: ""); s.isEnabled = false
        menu.addItem(s)
        if !status.accessibilityTrusted {
            let allow = NSMenuItem(title: "Allow Accessibility Access…", action: #selector(allowAccessibility), keyEquivalent: "")
            allow.target = self
            allow.toolTip = "Opens System Settings and shows the steps to turn it on."
            menu.addItem(allow)
        }
        if status.macMouseFixRunning {
            let warn = NSMenuItem(title: "Mac Mouse Fix is also running", action: #selector(showGuide), keyEquivalent: "")
            warn.target = self
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            warn.toolTip = "Both apps react to the same buttons and scrolling. Quit Mac Mouse Fix or turn off its Buttons and Scrolling switches."
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.toolTip = "Choose what your buttons, scroll wheel and pointer do."
        menu.addItem(settings)
        let guide = NSMenuItem(title: "How to Use MouseDragFix…", action: #selector(showGuide), keyEquivalent: "")
        guide.target = self
        guide.toolTip = "Getting started, what your mouse does right now, and fixes for common problems."
        menu.addItem(guide)
        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let about = NSMenuItem(title: "MouseDragFix \(version)", action: nil, keyEquivalent: ""); about.isEnabled = false
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit MouseDragFix", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        quit.toolTip = "Your mouse goes back to normal until you open MouseDragFix again."
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { store.config.enabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
