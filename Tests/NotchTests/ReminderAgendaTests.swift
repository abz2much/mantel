import Foundation
import Testing
@testable import Notch

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/London")!
    return c
}
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
private let now = at(8, 12)

private func item(_ title: String, due: Date?, hasTime: Bool = true) -> ReminderItem {
    ReminderItem(id: title, title: title, due: due, hasTime: hasTime, listColor: nil)
}

@Test func showsOverdueAndDueTodayOnly() {
    let items = [item("tomorrow", due: at(9, 9)), item("no date", due: nil), item("today", due: at(8, 15)),
                 item("yesterday", due: at(7, 10))]
    let agenda = ReminderAgenda.make(items, now: now, max: 5, calendar: cal)
    #expect(agenda.shown.map(\.title) == ["yesterday", "today"])
}

@Test func overdueFirstThenByTime() {
    let items = [item("later today", due: at(8, 17)), item("this morning", due: at(8, 9)),
                 item("all day today", due: at(8, 0), hasTime: false), item("last week", due: at(1, 9))]
    let agenda = ReminderAgenda.make(items, now: now, max: 5, calendar: cal)
    // A timed reminder whose time has passed is overdue; an all-day one is due until the day ends.
    #expect(agenda.shown.map(\.title) == ["last week", "this morning", "all day today", "later today"])
}

@Test func capsAndCountsTheRest() {
    let items = (1...6).map { item("r\($0)", due: at(8, 12 + $0)) }
    let agenda = ReminderAgenda.make(items, now: now, max: 3, calendar: cal)
    #expect(agenda.shown.count == 3)
    #expect(agenda.moreCount == 3)
}

@Test func labelsSayWhen() {
    #expect(ReminderAgenda.label(item("a", due: at(7, 10)), now: now, calendar: cal) == .overdue)
    #expect(ReminderAgenda.label(item("b", due: at(8, 9)), now: now, calendar: cal) == .overdue)
    #expect(ReminderAgenda.label(item("c", due: at(8, 15, 30)), now: now, calendar: cal) == .time(at(8, 15, 30)))
    #expect(ReminderAgenda.label(item("d", due: at(8, 0), hasTime: false), now: now, calendar: cal) == .today)
}

@Test func agendaMakesRoomForReminders() {
    let meetings = (1...5).map { i in
        MeetingEvent(id: "m\(i)", title: "m\(i)", start: at(8, 12 + i), end: at(8, 12 + i, 30), link: nil,
                     calendarTitle: "Work", attendeeCount: 2, isDeclined: false, calendarColor: nil)
    }
    let roomy = Agenda.make(meetings, now: now, calendar: cal)
    #expect(roomy.later.count == 3)
    let tight = Agenda.make(meetings, now: now, maxLater: 1, calendar: cal)
    #expect(tight.later.count == 1)
    #expect(tight.moreCount == 3)
}
