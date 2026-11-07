import SwiftUI

struct MusicCardView: View {
    @ObservedObject var music: MusicService
    /// Song time under the pointer while dragging the progress bar.
    @State private var scrub: TimeInterval?
    @State private var hoveringBar = false

    var body: some View {
        if let track = music.track {
            HStack(spacing: 14) {
                cover(track)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(text: track.title, font: .headline)
                        MarqueeText(text: track.artist, font: .caption).foregroundStyle(.secondary)
                    }
                    // New song: the old title fades out and the new one slides up.
                    .id("\(track.title)|\(track.artist)")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    if track.isLive { liveLabel } else { progress(track) }
                    controls(track)
                }
            }
            .frame(width: 380)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(alignment: .leading) {
                ColourWash(colour: music.accent, centreX: 12 + 36)   // centred on the cover
            }
            .animation(.easeInOut(duration: 0.6), value: music.accent)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Album art when available, otherwise a placeholder tile, so the layout never shifts.
    private func cover(_ track: TrackInfo) -> some View {
        Group {
            if music.showAlbumArt, let art = music.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .id(music.artwork)   // a new cover crossfades in
        .transition(.opacity)
        .shadow(color: (music.accent ?? .clear).opacity(0.8), radius: 16)   // the glow
        .scaleEffect(track.state == .playing ? 1 : 0.88)   // sits back a little while paused
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: track.state)
    }

    /// In place of the progress bar for live radio, which has no length to show or seek in.
    private var liveLabel: some View {
        HStack(spacing: 5) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
        }
        .foregroundStyle(.secondary)
        .frame(height: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ track: TrackInfo) -> some View {
        let shown = scrub ?? music.position
        let fraction = track.duration > 0 ? min(1, max(0, shown / track.duration)) : 0
        return HStack(spacing: 8) {
            Text(Self.clock(shown))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(music.accent ?? .white).frame(width: geo.size.width * fraction)
                }
                .frame(height: hoveringBar || scrub != nil ? 7 : 4)   // thickens under the pointer
                .overlay(alignment: .leading) {
                    if scrub != nil {   // handle while dragging
                        Circle().fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .offset(x: geo.size.width * fraction - 6)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: hoveringBar || scrub != nil)
                .frame(maxHeight: .infinity)   // the whole row height is clickable
                .contentShape(Rectangle())
                .onHover { hoveringBar = $0 }
                .gesture(
                    // Click to jump, drag to scrub; the app only seeks on release.
                    DragGesture(minimumDistance: 0)
                        .onChanged { scrub = Self.seekTime(x: $0.location.x, width: geo.size.width, duration: track.duration) }
                        .onEnded { value in
                            music.seek(to: Self.seekTime(x: value.location.x, width: geo.size.width, duration: track.duration))
                            scrub = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(scrub == nil ? .linear(duration: 1) : nil, value: fraction)
            Text("-" + Self.clock(max(0, track.duration - shown)))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func controls(_ track: TrackInfo) -> some View {
        HStack(spacing: 28) {
            Spacer()
            Button { music.previous() } label: { Image(systemName: "backward.fill") }
            Button { music.playPause() } label: {
                Image(systemName: track.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(music.accent ?? .primary)
            }
            Button { music.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
    }

    /// Song time for a click or drag at `x` along a bar `width` wide.
    static func seekTime(x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(1, max(0, x / width)) * duration
    }

    private static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Compact-state indicators shown either side of the notch while Spotify or Apple Music is active; empty when idle.
struct MusicCompactLeading: View {
    @ObservedObject var music: MusicService

    var body: some View {
        // A tiny cover when album art is on; the music note otherwise.
        if !music.showsCard {
            EmptyView()
        } else if music.showAlbumArt, let art = music.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(music.track?.state == .playing ? 1 : 0.5)
                .transition(.opacity)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(music.track?.state == .playing ? music.accent ?? .green : .secondary)
        }
    }
}

struct MusicCompactTrailing: View {
    @ObservedObject var music: MusicService

    var body: some View {
        let playing = music.track?.state == .playing
        if music.showsCard {
            indicator(playing: playing)
        }
    }

    private func indicator(playing: Bool) -> some View {
        Image(systemName: playing ? "waveform" : "pause.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(playing ? music.accent ?? .green : .secondary)
            .symbolEffect(.variableColor.iterative, isActive: playing)
    }
}

/// Expanded content, chosen by `NotchController`: meeting popup, music card, or the hover panel.
struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var timer: TimerService
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch state.content {
        case .meeting where state.event != nil:
            NotchView(state: state, onJoin: onJoin, onDismiss: onDismiss)
        case .panel:
            HoverPanelView(state: state, music: music, calendar: calendar, clipboard: clipboard, timer: timer, onJoin: onJoin)
        case .timerDone:
            TimerDoneView(timer: timer)
        default:
            MusicCardView(music: music)
        }
    }
}
