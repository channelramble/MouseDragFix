import Cocoa

// `MouseDragFix --post missionControl` posts one hotkey and exits (used for testing).
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--post" {
    let names: [String: SymbolicHotKey] = ["missionControl": .missionControl, "appExpose": .appExpose,
                                           "showDesktop": .showDesktop, "left": .moveLeftASpace, "right": .moveRightASpace]
    guard let hk = names[args[2]] else { Log.info("unknown hotkey \(args[2])"); exit(1) }
    HotKeyPoster.post(hk)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
