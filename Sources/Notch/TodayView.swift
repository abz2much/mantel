import SwiftUI

/// The Today tab: what's left of today's meetings, with Join buttons.
struct TodayView: View {
    let events: [MeetingEvent]
    let calendarAccess: Bool
    let onJoin: (URL) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            agendaSection(Agenda.make(events, now: context.date), now: context.date)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agendaSection(_ agenda: Agenda, now: Date) -> some View {
        if !calendarAccess {
            EmptyMessage(text: "Calendar access is off", icon: "calendar.badge.exclamationmark")
        } else if agenda.current == nil, agenda.next == nil {
            EmptyMessage(text: "No more meetings today", icon: "checkmark.circle")
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
