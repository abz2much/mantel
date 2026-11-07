import AppKit

/// The countdown timer behind the Timer tab, the compact countdown and the "Time's up" popup.
@MainActor
final class TimerService: ObservableObject {
    /// How long "Time's up" stays once it's on screen, unless dismissed.
    static let doneShowsFor: TimeInterval = 10

    @Published private(set) var countdown = Countdown()
    /// "Time's up" is waiting to show or showing. It stays until it has been on screen for
    /// `doneShowsFor` or is dismissed, so a meeting reminder that's up at the time can't swallow it.
    @Published private(set) var doneShowing = false
    /// The finished timer was a focus session (offer a break) or the break itself.
    @Published private(set) var doneOffersBreak = false
    @Published private(set) var doneWasBreak = false

    /// Something changed that affects what the notch shows (started, stopped, finished, popup gone).
    var onChange: (() -> Void)?

    private let now: () -> Date
    private let chime: () -> Void
    private var onBreak = false
    private var endTimer: Timer?
    private var doneTimer: Timer?

    /// `now` and `chime` are swappable for tests.
    init(now: @escaping () -> Date = Date.init, chime: @escaping () -> Void = { NSSound(named: "Glass")?.play() }) {
        self.now = now
        self.chime = chime
    }

    func start(minutes: Int) { begin(minutes: minutes, isBreak: false) }

    /// From the popup: start the 5-minute break after a focus session.
    func startBreak() { begin(minutes: Countdown.breakMinutes, isBreak: true) }

    func pause() {
        countdown.pause(now: now())
        endTimer?.invalidate()
        onChange?()
    }

    func resume() {
        guard countdown.isPaused else { return }
        countdown.resume(now: now())
        scheduleEnd()
        onChange?()
    }

    func addMinute() {
        countdown.addMinute(now: now())
        if countdown.isRunning { scheduleEnd() }
        onChange?()
    }

    func stop() {
        countdown.stop()
        endTimer?.invalidate()
        onChange?()
    }

    func dismissDone() {
        doneTimer?.invalidate()
        doneTimer = nil
        guard doneShowing else { return }
        doneShowing = false
        onChange?()
    }

    /// Called once "Time's up" is actually on screen: from then it stays for `doneShowsFor`.
    func doneAppeared() {
        guard doneShowing, doneTimer == nil else { return }
        let timer = Timer(timeInterval: Self.doneShowsFor, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDone() }
        }
        RunLoop.main.add(timer, forMode: .common)
        doneTimer = timer
    }

    /// Ends the timer if its time is up. Run every second as well as from the end timer, because
    /// run-loop timers don't count time while the Mac sleeps.
    func checkFinished() {
        guard countdown.isRunning, countdown.isFinished(at: now()) else { return }
        finish()
    }

    private func begin(minutes: Int, isBreak: Bool) {
        dismissDone()
        onBreak = isBreak
        countdown.start(minutes: minutes, now: now())
        scheduleEnd()
        onChange?()
    }

    private func scheduleEnd() {
        endTimer?.invalidate()
        let left = countdown.remaining(at: now())
        let timer = Timer(timeInterval: left, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFinished() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps time while the menu bar menu is open
        endTimer = timer
    }

    private func finish() {
        endTimer?.invalidate()
        doneOffersBreak = !onBreak && countdown.offersBreak
        doneWasBreak = onBreak
        countdown.stop()
        doneTimer?.invalidate()
        doneTimer = nil
        doneShowing = true
        chime()
        onChange?()
    }
}
