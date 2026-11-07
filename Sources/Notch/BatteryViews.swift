import SwiftUI

/// The charging or low-battery flash, drawn in the compact areas either side of the notch.
/// A glow sweeps left to right across both sides (passing behind the camera), then the icon and level fade in.
struct BatteryCompactSide: View {
    enum Side { case leading, trailing }

    let alert: BatteryAlert
    let shownAt: Date
    let side: Side

    private static let width: CGFloat = 56
    /// Seconds after `shownAt`: when the glow crosses each side, and when the labels fade in.
    private static let leadingSweep = 0.0...0.5
    private static let trailingSweep = 0.7...1.2
    private static let labelFade = 0.9...1.3

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(shownAt)
            ZStack {
                glow(t: t)
                label
                    .opacity(Self.progress(t, in: Self.labelFade))
            }
            // Not clipped: the notch's own outline trims the glow, and the camera hides its inner edge.
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
        }
    }

    private var colour: Color {
        switch alert {
        case .charging: .green
        case .low: .red
        }
    }

    private var percent: Int {
        switch alert {
        case .charging(let p), .low(let p): p
        }
    }

    @ViewBuilder private var label: some View {
        switch side {
        case .leading:
            Image(systemName: { if case .charging = alert { "bolt.fill" } else { "battery.25percent" } }())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(colour)
        case .trailing:
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(colour)
        }
    }

    private func glow(t: TimeInterval) -> some View {
        let range = side == .leading ? Self.leadingSweep : Self.trailingSweep
        let p = Self.progress(t, in: range)
        let visible = p > 0 && p < 1
        return Capsule()
            .fill(colour)
            .frame(width: 34, height: 18)
            .blur(radius: 8)
            .offset(x: (p - 0.5) * (Self.width + 40))
            .opacity(visible ? 0.9 : 0)
    }

    /// 0 before `range`, 1 after it, linear in between.
    private static func progress(_ t: TimeInterval, in range: ClosedRange<TimeInterval>) -> Double {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
}

/// Left of the notch: the battery flash while one is showing, else a running timer, else the music indicator.
struct CompactLeading: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicService
    @ObservedObject var timer: TimerService
    @ObservedObject var flags: StageFlags

    var body: some View {
        if flags.showsBattery, let alert = state.battery {
            // Until the clock starts, the sweep waits (dark) rather than playing unseen.
            BatteryCompactSide(alert: alert, shownAt: state.batteryShownAt ?? .distantFuture, side: .leading)
        } else if timer.countdown.isActive {
            TimerCompactSide(timer: timer, side: .leading)
        } else {
            MusicCompactLeading(music: music)
        }
    }
}

/// Right of the notch: the battery level while a flash is showing, else a running timer's time left, else music.
struct CompactTrailing: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicService
    @ObservedObject var timer: TimerService
    @ObservedObject var flags: StageFlags

    var body: some View {
        if flags.showsBattery, let alert = state.battery {
            // Until the clock starts, the sweep waits (dark) rather than playing unseen.
            BatteryCompactSide(alert: alert, shownAt: state.batteryShownAt ?? .distantFuture, side: .trailing)
        } else if timer.countdown.isActive {
            TimerCompactSide(timer: timer, side: .trailing)
        } else {
            MusicCompactTrailing(music: music)
        }
    }
}
