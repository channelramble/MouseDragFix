import SwiftUI
import Carbon.HIToolbox

/// Click, then press a key combination. Reports the CGEvent-compatible key code and flags.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyShortcut?

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onRecord = { shortcut = $0 }
        v.shortcut = shortcut
        return v
    }
    func updateNSView(_ v: RecorderView, context: Context) { v.shortcut = shortcut; v.needsDisplay = true }

    final class RecorderView: NSView {
        var onRecord: ((KeyShortcut) -> Void)?
        var shortcut: KeyShortcut?
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); recording = true }
        override func resignFirstResponder() -> Bool { recording = false; return true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) { recording = false; window?.makeFirstResponder(nil); return }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            var flags: UInt64 = 0
            if mods.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
            if mods.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
            if mods.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
            if mods.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
            if mods.contains(.function) { flags |= CGEventFlags.maskSecondaryFn.rawValue }
            let s = KeyShortcut(keyCode: event.keyCode, modifiers: flags, display: Self.display(event: event, mods: mods))
            shortcut = s
            onRecord?(s)
            recording = false
            window?.makeFirstResponder(nil)
        }

        static func display(event: NSEvent, mods: NSEvent.ModifierFlags) -> String {
            var s = ""
            if mods.contains(.control) { s += "⌃" }
            if mods.contains(.option) { s += "⌥" }
            if mods.contains(.shift) { s += "⇧" }
            if mods.contains(.command) { s += "⌘" }
            let names: [UInt16: String] = [
                36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
                115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            ]
            s += names[event.keyCode] ?? (event.charactersIgnoringModifiers?.uppercased() ?? "?")
            return s
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()
            let text = recording ? "Type shortcut…" : (shortcut?.display ?? "Click to record")
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                        .foregroundColor: recording || shortcut != nil ? NSColor.labelColor : NSColor.secondaryLabelColor]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
