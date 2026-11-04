import Foundation
import Testing
@testable import Notch

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func meeting(_ id: String, startsIn seconds: TimeInterval, declined: Bool = false) -> MeetingEvent {
    MeetingEvent(
        id: id,
        title: "Meeting \(id)",
        start: now.addingTimeInterval(seconds),
        end: now.addingTimeInterval(seconds + 1800),
        link: nil,
        calendarTitle: "Work",
        attendeeCount: 2,
        isDeclined: declined,
        calendarColor: nil
    )
}

@Test func showsFiveMinuteReminder() {
    let pick = ReminderPicker.pick([meeting("a", startsIn: 295)], now: now, dismissed: [])
    #expect(pick?.key == ReminderKey(eventID: "a", window: 0))
}

@Test func showsNothingBetweenWindows() {
    #expect(ReminderPicker.pick([meeting("a", startsIn: 200)], now: now, dismissed: []) == nil)
}

@Test func showsOverrunAfterStart() {
    let pick = ReminderPicker.pick([meeting("a", startsIn: -30)], now: now, dismissed: [])
    #expect(pick?.key == ReminderKey(eventID: "a", window: 1))
}

@Test func dismissingFiveMinuteReminderKeepsFinalMinute() {
    let dismissed: Set = [ReminderKey(eventID: "a", window: 0)]
    let pick = ReminderPicker.pick([meeting("a", startsIn: 30)], now: now, dismissed: dismissed)
    #expect(pick?.key == ReminderKey(eventID: "a", window: 1))
}

@Test func dismissingFinalMinuteHidesIt() {
    let dismissed: Set = [ReminderKey(eventID: "a", window: 1)]
    #expect(ReminderPicker.pick([meeting("a", startsIn: 30)], now: now, dismissed: dismissed) == nil)
}

@Test func skipsDeclinedMeeting() {
    #expect(ReminderPicker.pick([meeting("a", startsIn: 30, declined: true)], now: now, dismissed: []) == nil)
}

@Test func prefersUpcomingMeetingOverStartedOne() {
    let events = [meeting("started", startsIn: -30), meeting("upcoming", startsIn: 30)]
    let pick = ReminderPicker.pick(events, now: now, dismissed: [])
    #expect(pick?.event.id == "upcoming")
}
