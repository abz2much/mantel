import SwiftUI

/// The small tab at the top of a monitor: the battery sweep during an alert, otherwise album art,
/// song title and the timer, whichever are running.
struct MonitorTabView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicService
    @ObservedObject var timer: TimerService
    @ObservedObject var flags: StageFlags

    var body: some View {
        if flags.showsBattery, let alert = state.battery {
            HStack(spacing: 0) {
                BatteryCompactSide(alert: alert, shownAt: state.batteryShownAt ?? .distantFuture, side: .leading)
                BatteryCompactSide(alert: alert, shownAt: state.batteryShownAt ?? .distantFuture, side: .trailing)
            }
        } else {
            HStack(spacing: 8) {
                if music.showsCard {
                    MusicCompactLeading(music: music)
                    Text(Self.short(music.track?.title ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                if timer.countdown.isActive {
                    HStack(spacing: 4) {
                        TimerCompactSide(timer: timer, side: .leading)
                        TimerCompactSide(timer: timer, side: .trailing)
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    /// The tab sits inside a fixed-size layout, so long titles are cut here rather than by the frame.
    static func short(_ title: String, limit: Int = 28) -> String {
        title.count > limit ? String(title.prefix(limit - 1)) + "…" : title
    }
}
