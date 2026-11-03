import EventKit
import Foundation
import os

struct MeetingEvent: Equatable, Identifiable {
    let id: String          // stable per occurrence (recurring events share eventIdentifier)
    let title: String
    let start: Date
    let link: MeetingLink?
    let calendarTitle: String
    let attendeeCount: Int
    let isDeclined: Bool    // the user's own response is "declined"
    let calendarColor: RGB?
}

/// Read-only wrapper over EventKit. Never creates, edits or deletes events.
@MainActor
final class CalendarService: ObservableObject {
    private static let log = Logger(subsystem: "local.notch.app", category: "calendar")
    private static let deselectedKey = "deselectedCalendarIDs"

    private let store = EKEventStore()

    @Published private(set) var hasAccess = false
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var events: [MeetingEvent] = []
    @Published private(set) var deselected: Set<String>

    /// Called after every refetch.
    var onUpdate: (() -> Void)?

    private var observer: NSObjectProtocol?
    private var timer: Timer?

    init() {
        // Track new calendars by default: store the ones the user turned off.
        deselected = Set(UserDefaults.standard.stringArray(forKey: Self.deselectedKey) ?? [])
    }

    func start() async {
        do {
            hasAccess = try await store.requestFullAccessToEvents()
        } catch {
            Self.log.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
            hasAccess = false
        }
        guard hasAccess else { return }

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

    func isSelected(_ calendar: EKCalendar) -> Bool {
        !deselected.contains(calendar.calendarIdentifier)
    }

    func setSelected(_ selected: Bool, for calendar: EKCalendar) {
        if selected { deselected.remove(calendar.calendarIdentifier) } else { deselected.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(deselected), forKey: Self.deselectedKey)
        refresh()
    }

    func refresh() {
        guard hasAccess else { return }
        calendars = store.calendars(for: .event)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }

        let tracked = calendars.filter(isSelected)
        guard !tracked.isEmpty else {
            events = []
            onUpdate?()
            return
        }

        let now = Date()
        let from = now.addingTimeInterval(-60)  // keep just-started events for the overrun display
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(24 * 3600), calendars: tracked)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.startDate > from }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                MeetingEvent(
                    id: "\(event.eventIdentifier ?? event.title ?? "?")|\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled event",
                    start: event.startDate,
                    link: MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes),
                    calendarTitle: event.calendar.title,
                    attendeeCount: event.attendees?.count ?? 0,
                    isDeclined: event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined,
                    calendarColor: event.calendar.color.usingColorSpace(.sRGB).map {
                        RGB(r: $0.redComponent, g: $0.greenComponent, b: $0.blueComponent)
                    }
                )
            }
        onUpdate?()
    }
}
