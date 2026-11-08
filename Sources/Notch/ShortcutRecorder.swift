import AppKit
import Carbon
import SwiftUI

/// Settings box for the clipboard shortcut: click it, press the new keys; Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var clipboard: ClipboardService
    @State private var monitor: Any?
    @State private var refused = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if clipboard.shortcut != .default, !clipboard.recordingShortcut {
                    Button("Reset") { clipboard.shortcut = .default }
                        .controlSize(.small)
                        .help("Go back to ⌃⌥V")
                }
                Button {
                    clipboard.recordingShortcut ? stop() : start()
                } label: {
                    Text(clipboard.recordingShortcut ? "Type a shortcut…" : clipboard.shortcut.display)
                        .frame(minWidth: 96)
                }
                .help(clipboard.recordingShortcut ? "Press the keys, or Esc to cancel" : "Click to change")
            }
            if clipboard.recordingShortcut, refused {
                note("Use ⌃, ⌥ or ⌘ with a key.")
            } else if clipboard.shortcutTaken, !clipboard.recordingShortcut {
                note("Another app uses this shortcut. Pick another.")
            }
        }
        .onDisappear { stop() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.orange)
    }

    private func start() {
        refused = false
        clipboard.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let shortcut = Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
            if shortcut.isAllowed {
                clipboard.shortcut = shortcut
                stop()
            } else {
                refused = true
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if clipboard.recordingShortcut { clipboard.recordingShortcut = false }
    }
}
