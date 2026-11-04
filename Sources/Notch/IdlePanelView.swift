import SwiftUI

/// Shown when hovering the idle notch: a paused song to resume, then what's left of today.
struct IdlePanelView: View {
    let events: [MeetingEvent]
    let calendarAccess: Bool
    @ObservedObject var spotify: SpotifyService
    let onJoin: (URL) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if let track = spotify.track {
                    resumeRow(track)
                    Divider().overlay(.white.opacity(0.15))
                }
                agendaSection(Agenda.make(events, now: context.date), now: context.date)
            }
            .frame(width: 360, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: Music

    private func resumeRow(_ track: TrackInfo) -> some View {
        HStack(spacing: 10) {
            Group {
                if spotify.showAlbumArt, let art = spotify.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.12)
                        Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { spotify.playPause() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(spotify.accent ?? .white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Resume")
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agendaSection(_ agenda: Agenda, now: Date) -> some View {
        if !calendarAccess {
            Label("Calendar access is off", systemImage: "calendar.badge.exclamationmark")
                .font(.caption).foregroundStyle(.secondary)
        } else if agenda.current == nil, agenda.next == nil {
            Label("No more meetings today", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let meeting = agenda.current {
                    meetingRow(meeting, badge: "NOW", detail: "until \(Self.time(meeting.end))")
                }
                if let meeting = agenda.next {
                    meetingRow(meeting, badge: "NEXT", detail: "\(Self.time(meeting.start)) · \(Agenda.countdown(to: meeting.start, from: now))")
                }
                ForEach(agenda.later) { laterRow($0) }
                if agenda.moreCount > 0 {
                    Text("+\(agenda.moreCount) more today").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func meetingRow(_ meeting: MeetingEvent, badge: String, detail: String) -> some View {
        HStack(spacing: 8) {
            calendarDot(meeting)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(badge).font(.system(size: 9, weight: .bold)).tracking(1)
                    Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(meeting.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let link = meeting.link {
                Button("Join") { onJoin(link.url) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .help("Join \(link.provider)")
            }
        }
    }

    private func laterRow(_ meeting: MeetingEvent) -> some View {
        HStack(spacing: 8) {
            calendarDot(meeting)
            Text(Self.time(meeting.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(meeting.title).font(.caption).lineLimit(1)
        }
    }

    private func calendarDot(_ meeting: MeetingEvent) -> some View {
        Circle()
            .fill(meeting.calendarColor.map(Color.init) ?? .white.opacity(0.4))
            .frame(width: 7, height: 7)
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
