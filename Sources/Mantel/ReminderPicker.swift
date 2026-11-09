import Foundation

/// One reminder window of one meeting occurrence; what the dismiss button hides.
struct ReminderKey: Hashable {
    let eventID: String
    let window: Int
}

struct Reminder: Equatable {
    let event: MeetingEvent
    let key: ReminderKey
}

/// Decides which meeting reminder, if any, the notch should show right now.
enum ReminderPicker {
    /// Seconds-before-start windows in which the meeting popup shows: 5 min mark (10 s), then the final minute plus 60 s overrun.
    static let windows: [ClosedRange<TimeInterval>] = [290...300, -60...60]

    /// `events` must be sorted by start time. A meeting that hasn't started yet wins over one in its overrun.
    static func pick(_ events: [MeetingEvent], now: Date, dismissed: Set<ReminderKey>) -> Reminder? {
        let candidates = events.compactMap { event -> Reminder? in
            guard !event.isDeclined else { return nil }
            let remaining = event.start.timeIntervalSince(now)
            guard let window = windows.firstIndex(where: { $0.contains(remaining) }) else { return nil }
            let key = ReminderKey(eventID: event.id, window: window)
            return dismissed.contains(key) ? nil : Reminder(event: event, key: key)
        }
        return candidates.first { $0.event.start > now } ?? candidates.first
    }
}
