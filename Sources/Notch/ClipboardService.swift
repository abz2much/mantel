import AppKit

/// Keeps recent text copies while Mantel runs. Nothing is saved to disk and copied text is never logged.
@MainActor
final class ClipboardService: ObservableObject {
    private static let enabledKey = "clipboardHistory"
    /// macOS has no "clipboard changed" notification; checking its change counter is cheap.
    private static let checkInterval: TimeInterval = 0.5

    @Published private(set) var items: [ClipboardItem] = []
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            enabled ? startWatching() : stopWatching()
        }
    }

    private var history = ClipboardHistory()
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?

    /// `pasteboard` is the system clipboard except in tests.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
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
