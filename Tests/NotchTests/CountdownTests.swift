import Foundation
import Testing
@testable import Notch

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

@Test func countsDownFromTheChosenLength() {
    var timer = Countdown()
    timer.start(minutes: 25, now: at(0))
    #expect(timer.remaining(at: at(60)) == 24 * 60)
    #expect(timer.isRunning)
}

@Test func pausingFreezesTheTimeLeft() {
    var timer = Countdown()
    timer.start(minutes: 5, now: at(0))
    timer.pause(now: at(60))
    #expect(timer.remaining(at: at(600)) == 4 * 60)
    #expect(timer.isPaused)
    timer.resume(now: at(600))
    #expect(timer.remaining(at: at(660)) == 3 * 60)
}

@Test func addingAMinuteExtendsIt() {
    var timer = Countdown()
    timer.start(minutes: 5, now: at(0))
    timer.addMinute(now: at(0))
    #expect(timer.remaining(at: at(0)) == 6 * 60)
    timer.pause(now: at(60))
    timer.addMinute(now: at(60))
    #expect(timer.remaining(at: at(500)) == 6 * 60)
}

@Test func stoppingClearsIt() {
    var timer = Countdown()
    timer.start(minutes: 5, now: at(0))
    timer.stop()
    #expect(!timer.isActive)
    #expect(timer.remaining(at: at(10)) == 0)
}

@Test func finishesAtZeroAndNeverGoesNegative() {
    var timer = Countdown()
    timer.start(minutes: 1, now: at(0))
    #expect(!timer.isFinished(at: at(59)))
    #expect(timer.isFinished(at: at(60)))
    #expect(timer.remaining(at: at(90)) == 0)
}

@Test func aPausedTimerNeverFinishes() {
    var timer = Countdown()
    timer.start(minutes: 1, now: at(0))
    timer.pause(now: at(30))
    #expect(!timer.isFinished(at: at(3600)))
}

@Test func readsLikeAClock() {
    #expect(Countdown.clock(24 * 60 + 12) == "24:12")
    #expect(Countdown.clock(5) == "0:05")
    #expect(Countdown.clock(65 * 60) == "1:05:00")
    #expect(Countdown.clock(0.4) == "0:01")   // rounds up, so it never shows 0:00 while running
}

@Test func aPomodoroOffersABreak() {
    var timer = Countdown()
    timer.start(minutes: 25, now: at(0))
    #expect(timer.offersBreak)
    timer.start(minutes: 15, now: at(0))
    #expect(!timer.offersBreak)
}
