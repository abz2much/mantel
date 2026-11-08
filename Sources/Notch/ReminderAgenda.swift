import Foundation

/// An incomplete Apple Reminders item, reduced to what the Today tab shows.
struct ReminderItem: Equatable, Identifiable {
    let id: String
    let title: String
    let due: Date?
    /// False for reminders due on a day with no time.
    let hasTime: Bool
    let listColor: RGB?
}

/// Which reminders the Today tab shows: overdue first, then the rest of today in time order.
struct ReminderAgenda: Equatable {
    var shown: [ReminderItem] = []
    var moreCount = 0

    enum Label: Equatable {
        case overdue
        case today
        case time(Date)
    }

    static func make(_ items: [ReminderItem], now: Date, max: Int, calendar: Calendar = .current) -> ReminderAgenda {
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return ReminderAgenda()
        }
        let due = items
            .filter { item in item.due.map { $0 < endOfToday } ?? false }
            .sorted { a, b in
                let (ao, bo) = (isOverdue(a, now: now, calendar: calendar), isOverdue(b, now: now, calendar: calendar))
                if ao != bo { return ao }
                return a.due! < b.due!
            }
        return ReminderAgenda(shown: Array(due.prefix(max)), moreCount: Swift.max(0, due.count - max))
    }

    static func label(_ item: ReminderItem, now: Date, calendar: Calendar = .current) -> Label {
        guard let due = item.due else { return .today }
        if isOverdue(item, now: now, calendar: calendar) { return .overdue }
        return item.hasTime ? .time(due) : .today
    }

    /// A timed reminder is overdue once its time passes; an all-day one only once its day is over.
    private static func isOverdue(_ item: ReminderItem, now: Date, calendar: Calendar) -> Bool {
        guard let due = item.due else { return false }
        return item.hasTime ? due < now : due < calendar.startOfDay(for: now)
    }
}
