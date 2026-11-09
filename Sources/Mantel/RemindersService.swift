import AppKit
import EventKit
import os

/// Reads today's and overdue Apple Reminders for the Today tab, and can tick one off.
/// Off until turned on in Settings; macOS asks for Reminders access at that point, not before.
@MainActor
final class RemindersService: ObservableObject {
    private static let log = Logger(subsystem: "local.mantel.app", category: "reminders")
    private static let enabledKey = "remindersEnabled"
    private static let deselectedKey = "deselectedReminderLists"

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if enabled { Task { await start() } } else { stop() }
        }
    }
    @Published private(set) var hasAccess = false
    /// True once access has been asked for, so Settings can tell "not asked yet" from "refused".
    @Published private(set) var asked = false
    @Published private(set) var lists: [EKCalendar] = []
    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var deselected: Set<String>

    var onUpdate: (() -> Void)?

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var starting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        deselected = Set(defaults.stringArray(forKey: Self.deselectedKey) ?? [])
    }

    func start() async {
        guard enabled, observer == nil, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            hasAccess = try await store.requestFullAccessToReminders()
        } catch {
            Self.log.error("reminders access request failed: \(error.localizedDescription, privacy: .public)")
            hasAccess = false
        }
        asked = true
        guard hasAccess, enabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        items = []
        onUpdate?()
    }

    func isSelected(listID: String) -> Bool { !deselected.contains(listID) }

    func setSelected(_ selected: Bool, listID: String) {
        if selected { deselected.remove(listID) } else { deselected.insert(listID) }
        defaults.set(Array(deselected), forKey: Self.deselectedKey)
        refresh()
    }

    func refresh() {
        guard enabled, hasAccess else { return }
        lists = store.calendars(for: .reminder)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
        let tracked = lists.filter { isSelected(listID: $0.calendarIdentifier) }
        guard !tracked.isEmpty else {
            items = []
            onUpdate?()
            return
        }
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: tracked)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let mapped = (reminders ?? []).compactMap(Self.item)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.items = mapped
                    self.onUpdate?()
                }
            }
        }
    }

    /// Adds a reminder due today to a list shown in Today, so it appears straight away.
    /// Returns false if it couldn't be saved, so the typed text can be kept.
    @discardableResult
    func add(_ typed: String) -> Bool {
        let shown = lists.map(\.calendarIdentifier).filter { isSelected(listID: $0) }
        guard enabled, hasAccess, let title = ReminderAgenda.newTitle(from: typed),
              let listID = ReminderAgenda.listForNew(defaultID: store.defaultCalendarForNewReminders()?.calendarIdentifier,
                                                     shown: shown),
              let list = lists.first(where: { $0.calendarIdentifier == listID }) else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        do {
            try store.save(reminder, commit: true)
            refresh()
            return true
        } catch {
            Self.log.error("couldn't add reminder: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Marks a reminder done in Apple Reminders.
    func complete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            items.removeAll { $0.id == id }
            onUpdate?()
        } catch {
            Self.log.error("couldn't complete reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func item(_ reminder: EKReminder) -> ReminderItem? {
        guard let components = reminder.dueDateComponents,
              let due = Calendar.current.date(from: components) else { return nil }
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled reminder",
            due: due,
            hasTime: components.hour != nil,
            listColor: reminder.calendar.color.usingColorSpace(.sRGB).map {
                RGB(r: $0.redComponent, g: $0.greenComponent, b: $0.blueComponent)
            }
        )
    }
}
