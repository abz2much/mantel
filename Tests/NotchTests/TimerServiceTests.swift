import Foundation
import Testing
@testable import Notch

/// A clock the test moves by hand.
@MainActor
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func makeTimer() -> (TimerService, FakeClock) {
    let clock = FakeClock()
    return (TimerService(now: { clock.now }, chime: {}), clock)
}

@MainActor @Test func endsWhenTheTimeIsUpEvenIfTheEndTimerWasLate() {
    // After sleep the run-loop timer fires late; the regular check still ends it on time.
    let (timer, clock) = makeTimer()
    timer.start(minutes: 5)
    clock.advance(5 * 60)
    timer.checkFinished()
    #expect(timer.doneShowing)
    #expect(!timer.countdown.isActive)
}

@MainActor @Test func doesntEndEarly() {
    let (timer, clock) = makeTimer()
    timer.start(minutes: 5)
    clock.advance(5 * 60 - 1)
    timer.checkFinished()
    #expect(!timer.doneShowing)
    #expect(timer.countdown.isRunning)
}

@MainActor @Test func timesUpWaitsUntilItsBeenShown() {
    // If a meeting reminder is up when the timer ends, "Time's up" must still be there afterwards.
    let (timer, clock) = makeTimer()
    timer.start(minutes: 5)
    clock.advance(5 * 60 + 30)
    timer.checkFinished()
    clock.advance(60)
    timer.checkFinished()
    #expect(timer.doneShowing)
}

@MainActor @Test func aFocusSessionOffersABreakAndTheBreakSaysSo() {
    let (timer, clock) = makeTimer()
    timer.start(minutes: 25)
    clock.advance(25 * 60)
    timer.checkFinished()
    #expect(timer.doneOffersBreak)
    #expect(!timer.doneWasBreak)
    timer.startBreak()
    #expect(!timer.doneShowing)
    clock.advance(5 * 60)
    timer.checkFinished()
    #expect(timer.doneShowing)
    #expect(timer.doneWasBreak)
    #expect(!timer.doneOffersBreak)
}

@MainActor @Test func aPausedTimerDoesntEnd() {
    let (timer, clock) = makeTimer()
    timer.start(minutes: 5)
    timer.pause()
    clock.advance(3600)
    timer.checkFinished()
    #expect(!timer.doneShowing)
}
