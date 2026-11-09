import AppKit

/// Keeps recent text copies while Mantel runs. Nothing is saved to disk and copied text is never logged.
@MainActor
final class ClipboardService: ObservableObject {
    private static let enabledKey = "clipboardHistory"
    private static let shortcutKey = "clipboardShortcut"
    private static let shortcutKeysKey = "clipboardShortcutKeys"
    /// macOS has no "clipboard changed" notification; checking its change counter is cheap.
    private static let checkInterval: TimeInterval = 0.5

    @Published private(set) var items: [ClipboardItem] = []
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            enabled ? startWatching() : stopWatching()
        }
    }

    /// "Open with ⌃⌥V": the shortcut that opens the clipboard panel. Only works while history is on.
    @Published var shortcutEnabled: Bool {
        didSet { defaults.set(shortcutEnabled, forKey: Self.shortcutKey) }
    }

    /// Which keys open it; ⌃⌥V unless changed in Settings.
    @Published var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.shortcutKeysKey) }
    }

    /// True while Settings is recording a new shortcut, so the old one doesn't fire meanwhile.
    @Published var recordingShortcut = false
    /// Set when another app already owns the chosen shortcut, so Settings can say so.
    @Published var shortcutTaken = false

    var opensWithShortcut: Bool { enabled && shortcutEnabled && !recordingShortcut }

    private let defaults: UserDefaults
    private var history = ClipboardHistory()
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?

    /// `pasteboard` is the system clipboard except in tests.
    init(pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        shortcutEnabled = defaults.object(forKey: Self.shortcutKey) as? Bool ?? true
        // A saved shortcut that isn't allowed (damaged or from an older rule) falls back to ⌃⌥V.
        shortcut = (defaults.data(forKey: Self.shortcutKeysKey))
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            .flatMap { $0.isAllowed ? $0 : nil }
            ?? .default
        // Whatever was on the clipboard before Mantel started isn't recorded.
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        if enabled { startWatching() }
    }

    /// Puts an earlier copy back on the clipboard, ready for ⌘V. It moves to the top of the list.
    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        check()
    }

    func clear() {
        history.clear()
        items = []
    }

    private func startWatching() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        clear()
    }

    /// Records the clipboard if it changed since last time. Runs on a timer while watching.
    func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Types first: private, temporary, file and other-device copies are never read at all.
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard ClipboardHistory.shouldRead(types: types),
              let text = pasteboard.string(forType: .string),   // nil when it isn't text: images
              pasteboard.changeCount == count                   // something newer arrived mid-read
        else { return }
        history.record(text, types: types, at: Date())
        if items != history.items { items = history.items }
    }
}
