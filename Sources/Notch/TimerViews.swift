import SwiftUI

/// The Timer tab: quick lengths to start, or the running countdown with its controls.
struct TimerTabView: View {
    @ObservedObject var timer: TimerService
    static let presets = [5, 15, 25, 45]

    var body: some View {
        if timer.countdown.isActive {
            running
        } else {
            VStack(spacing: 10) {
                Text("Start a timer").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button { timer.start(minutes: minutes) } label: {
                            VStack(spacing: 1) {
                                Text("\(minutes)").font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text(minutes == Countdown.pomodoroMinutes ? "focus" : "min")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 70, height: 54)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(minutes == Countdown.pomodoroMinutes ? "25-minute focus session, then a 5-minute break" : "\(minutes) minutes")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 12) {
                Text(Countdown.clock(timer.countdown.remaining(at: context.date)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.countdown.isPaused ? .secondary : .primary)
                    .contentTransition(.numericText(countsDown: true))
                HStack(spacing: 10) {
                    if timer.countdown.isPaused {
                        control("Resume", "play.fill") { timer.resume() }
                    } else {
                        control("Pause", "pause.fill") { timer.pause() }
                    }
                    control("+1 min", "plus") { timer.addMinute() }
                    control("Stop", "stop.fill") { timer.stop() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func control(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "Time's up", dropped down from the notch for a few seconds when a timer ends.
struct TimerDoneView: View {
    @ObservedObject var timer: TimerService

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.orange.opacity(0.2))
                Image(systemName: "timer").font(.system(size: 18, weight: .semibold)).foregroundStyle(.orange)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time's up").font(.headline)
                Text(timer.doneOffersBreak ? "Focus session done" : "Your timer has finished")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            if timer.doneOffersBreak {
                Button("5-min break") { timer.startBreak() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            Button { timer.dismissDone() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
                .help("Dismiss")
        }
        .frame(minWidth: 380)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .environment(\.colorScheme, .dark)
    }
}

/// Beside the notch while a timer runs: a timer icon on the left, the time left on the right.
struct TimerCompactSide: View {
    enum Side { case leading, trailing }
    @ObservedObject var timer: TimerService
    let side: Side

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: timer.countdown.isPaused ? "pause.circle" : "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(timer.countdown.isPaused ? .secondary : Color.orange)
        case .trailing:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Countdown.clock(timer.countdown.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(timer.countdown.isPaused ? .secondary : Color.orange)
            }
        }
    }
}
