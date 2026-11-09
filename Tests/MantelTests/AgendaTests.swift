import Foundation
import Testing
@testable import Mantel

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
/// 2027-01-14 10:00 UTC, so midnight is 14 hours away.
private let now = Date(timeIntervalSince1970: 1_799_920_800)

private func meeting(_ id: String, startsIn minutes: Double, lasts length: Double = 30, declined: Bool = false) -> MeetingEvent {
    let start = now.addingTimeInterval(minutes * 60)
    return MeetingEvent(
        id: id, title: id, start: start, end: start.addingTimeInterval(length * 60),
        link: nil, calendarTitle: "Work", attendeeCount: 2, isDeclined: declined, calendarColor: nil)
}

private func agenda(_ events: [MeetingEvent]) -> Agenda {
    Agenda.make(events, now: now, calendar: utc)
}

@Test func inProgressMeetingIsNow() {
    #expect(agenda([meeting("standup", startsIn: -10)]).current?.id == "standup")
}

@Test func endedMeetingIsLeftOut() {
    let result = agenda([meeting("done", startsIn: -40, lasts: 30)])
    #expect(result.current == nil && result.next == nil)
}

@Test func nextIsTheFirstUpcomingAndTheRestAreLater() {
    let result = agenda([meeting("a", startsIn: 30), meeting("b", startsIn: 90), meeting("c", startsIn: 150)])
    #expect(result.next?.id == "a")
    #expect(result.later.map(\.id) == ["b", "c"])
}

@Test func declinedMeetingsAreSkipped() {
    let result = agenda([meeting("declined", startsIn: 30, declined: true), meeting("kept", startsIn: 60)])
    #expect(result.next?.id == "kept")
}

@Test func meetingsAfterMidnightAreLeftOut() {
    let result = agenda([meeting("today", startsIn: 60), meeting("tomorrow", startsIn: 15 * 60)])
    #expect(result.next?.id == "today")
    #expect(result.later.isEmpty)
}

@Test func laterIsCappedAtThreeWithTheRestCounted() {
    let events = (0..<6).map { meeting("m\($0)", startsIn: Double(30 + $0 * 60)) }
    let result = agenda(events)
    #expect(result.later.map(\.id) == ["m1", "m2", "m3"])
    #expect(result.moreCount == 2)
}

@Test func countdownLabels() {
    #expect(Agenda.countdown(to: now.addingTimeInterval(25 * 60), from: now) == "in 25m")
    #expect(Agenda.countdown(to: now.addingTimeInterval(80 * 60), from: now) == "in 1h 20m")
    #expect(Agenda.countdown(to: now.addingTimeInterval(120 * 60), from: now) == "in 2h")
    #expect(Agenda.countdown(to: now.addingTimeInterval(30), from: now) == "in 1m")   // never "in 0m"
}
