import AppKit

/// The countdown timer behind the Timer tab, the compact countdown and the "Time's up" popup.
@MainActor
final class TimerService: ObservableObject {
    /// How long "Time's up" stays unless dismissed.
    static let doneShowsFor: TimeInterval = 10

    @Published private(set) var countdown = Countdown()
    /// "Time's up" is showing; `doneOffersBreak` when it was a Pomodoro.
    @Published private(set) var doneShowing = false
    @Published private(set) var doneOffersBreak = false

    /// Something changed that affects what the notch shows (started, stopped, finished, popup gone).
    var onChange: (() -> Void)?

    private var endTimer: Timer?
    private var doneTimer: Timer?

    func start(minutes: Int) {
        dismissDone()
        countdown.start(minutes: minutes, now: Date())
        scheduleEnd()
        onChange?()
    }

    func pause() {
        countdown.pause(now: Date())
        endTimer?.invalidate()
        onChange?()
    }

    func resume() {
        countdown.resume(now: Date())
        scheduleEnd()
        onChange?()
    }

    func addMinute() {
        countdown.addMinute(now: Date())
        if countdown.isRunning { scheduleEnd() }
        onChange?()
    }

    func stop() {
        countdown.stop()
        endTimer?.invalidate()
        onChange?()
    }

    /// From the popup: start the 5-minute break after a Pomodoro.
    func startBreak() { start(minutes: Countdown.breakMinutes) }

    func dismissDone() {
        doneTimer?.invalidate()
        guard doneShowing else { return }
        doneShowing = false
        onChange?()
    }

    private func scheduleEnd() {
        endTimer?.invalidate()
        let left = countdown.remaining(at: Date())
        let timer = Timer(timeInterval: left, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps time while the menu bar menu is open
        endTimer = timer
    }

    private func finish() {
        guard countdown.isFinished(at: Date().addingTimeInterval(0.05)) else { scheduleEnd(); return }
        doneOffersBreak = countdown.offersBreak
        countdown.stop()
        doneShowing = true
        NSSound(named: "Glass")?.play()
        doneTimer?.invalidate()
        let timer = Timer(timeInterval: Self.doneShowsFor, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDone() }
        }
        RunLoop.main.add(timer, forMode: .common)
        doneTimer = timer
        onChange?()
    }
}
