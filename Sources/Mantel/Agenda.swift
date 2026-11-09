import Foundation

/// What's left of today, for the panel shown when hovering the idle notch.
struct Agenda: Equatable {
    /// A meeting in progress.
    var current: MeetingEvent?
    var next: MeetingEvent?
    /// Meetings after `next`, capped at `maxLater` (fewer when reminders need the room).
    var later: [MeetingEvent] = []
    /// How many more meetings today beyond `later`.
    var moreCount = 0

    static let maxLater = 3

    /// `events` must be sorted by start time.
    static func make(_ events: [MeetingEvent], now: Date, maxLater: Int = Agenda.maxLater,
                     calendar: Calendar = .current) -> Agenda {
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return Agenda() }
        let today = events.filter { !$0.isDeclined && $0.end > now && $0.start < midnight }
        let upcoming = today.filter { $0.start > now }
        let rest = upcoming.dropFirst()
        return Agenda(
            current: today.first { $0.start <= now },
            next: upcoming.first,
            later: Array(rest.prefix(maxLater)),
            moreCount: max(0, rest.count - maxLater)
        )
    }

    /// "in 25m", "in 1h 20m", "in 2h"; rounds up so it never says "in 0m".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "in \(m)m" }
        return m == 0 ? "in \(h)h" : "in \(h)h \(m)m"
    }
}
