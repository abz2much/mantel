import Foundation

/// A countdown timer: running (with an end time), paused (with the time left), or off.
struct Countdown {
    enum State: Equatable {
        case off
        case running(endsAt: Date)
        case paused(left: TimeInterval)
    }

    /// The Pomodoro length; finishing one offers a short break.
    static let pomodoroMinutes = 25
    static let breakMinutes = 5

    private(set) var state: State = .off
    /// Minutes it was started with.
    private(set) var minutes = 0

    var isRunning: Bool { if case .running = state { true } else { false } }
    var isPaused: Bool { if case .paused = state { true } else { false } }
    var isActive: Bool { state != .off }
    var offersBreak: Bool { minutes == Self.pomodoroMinutes }

    mutating func start(minutes: Int, now: Date) {
        self.minutes = minutes
        state = .running(endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    mutating func pause(now: Date) {
        guard case .running = state else { return }
        state = .paused(left: remaining(at: now))
    }

    mutating func resume(now: Date) {
        guard case .paused(let left) = state else { return }
        state = .running(endsAt: now.addingTimeInterval(left))
    }

    mutating func addMinute(now: Date) {
        switch state {
        case .running(let end): state = .running(endsAt: end.addingTimeInterval(60))
        case .paused(let left): state = .paused(left: left + 60)
        case .off: break
        }
    }

    mutating func stop() { state = .off }

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .off: 0
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let left): left
        }
    }

    func isFinished(at now: Date) -> Bool {
        if case .running(let end) = state { return now >= end }
        return false
    }

    /// "24:12", "0:05", or "1:05:00" from an hour; rounds up so a running timer never reads 0:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
