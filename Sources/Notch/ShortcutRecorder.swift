import AppKit
import Carbon
import SwiftUI

/// Settings box for the clipboard shortcut: click it, press the new keys; Esc or clicking away cancels.
/// A shortcut is only saved once it's known to work, so the old one keeps working otherwise.
struct ShortcutRecorder: View {
    @ObservedObject var clipboard: ClipboardService
    @State private var monitor: Any?
    @State private var observers: [NSObjectProtocol] = []
    @State private var problem: String?

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
            if clipboard.recordingShortcut, let problem {
                note(problem)
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
        // Only keys typed in this Settings window count; the notch panel's keys are left alone.
        guard let window = NSApp.keyWindow else { return }
        problem = nil
        clipboard.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let shortcut = Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
            if !shortcut.isAllowed {
                problem = "Add ⌃ or ⌥. ⌘ alone is kept for app shortcuts."
            } else if shortcut != clipboard.shortcut, !GlobalHotKey.isAvailable(shortcut) {
                problem = "Another app uses \(shortcut.display). Try another."
            } else {
                clipboard.shortcut = shortcut
                stop()
            }
            return nil
        }
        // Clicking away or closing Settings cancels, so the shortcut is never left switched off.
        let centre = NotificationCenter.default
        observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].map { name in
            centre.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { stop() }
            }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if clipboard.recordingShortcut { clipboard.recordingShortcut = false }
    }
}
