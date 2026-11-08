import SwiftUI

/// The Today tab: what's left of today's meetings, with Join buttons, then overdue and today's reminders.
struct TodayView: View {
    let events: [MeetingEvent]
    let calendarAccess: Bool
    let onJoin: (URL) -> Void
    /// Empty when reminders are off in Settings.
    var reminders: [ReminderItem] = []
    var onComplete: (String) -> Void = { _ in }
    /// Reminders are on and allowed: show the section (with "Add a reminder") even when nothing is due.
    var remindersOn = false
    var onAdd: (String) -> Void = { _ in }
    /// Set while the "Add a reminder" field has the keyboard, so the panel stays open.
    var typing: Binding<Bool> = .constant(false)
    @State private var hoveredReminder: String?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            // Reminders take the room of all but one "later" meeting.
            let hasReminders = remindersOn || !ReminderAgenda.make(reminders, now: now, max: 1).shown.isEmpty
            let agenda = Agenda.make(events, now: now, maxLater: hasReminders ? 1 : Agenda.maxLater)
            let meetingRows = (agenda.current == nil ? 0 : 1) + (agenda.next == nil ? 0 : 1) + agenda.later.count
                + (agenda.moreCount > 0 ? 1 : 0)
            // Keep within the panel's fixed height: fewer reminders when the meetings list is full.
            let due = ReminderAgenda.make(reminders, now: now, max: meetingRows == 0 ? 5 : meetingRows >= 3 ? 2 : 3)
            VStack(alignment: .leading, spacing: 10) {
                if hasReminders, calendarAccess, meetingRows == 0 {
                    Label("No more meetings today", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    agendaSection(agenda, now: now)
                }
                if hasReminders { remindersSection(due, now: now) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Reminders

    private func remindersSection(_ due: ReminderAgenda, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // "Add a reminder" sits in the heading row, so a full list can never push it out of sight.
            HStack(spacing: 8) {
                Text("REMINDERS").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if remindersOn { addField }
            }
            ForEach(due.shown) { reminderRow($0, now: now) }
            if due.moreCount > 0 {
                Text("+\(due.moreCount) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Type and press Return to add a reminder due today; Esc cancels.
    private var addField: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus.circle")
                .font(.system(size: 11))
                .foregroundStyle(MantelStyle.amber)
            TextField("Add a reminder", text: $draft)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 170)
                .focused($fieldFocused)
                .onSubmit {
                    onAdd(draft)
                    draft = ""
                    fieldFocused = false
                }
                .onExitCommand {
                    draft = ""
                    fieldFocused = false
                }
        }
        .onChange(of: fieldFocused) { _, focused in typing.wrappedValue = focused }
        .onDisappear { if typing.wrappedValue { typing.wrappedValue = false } }
    }

    private func reminderRow(_ item: ReminderItem, now: Date) -> some View {
        let colour = item.listColor.map(Color.init) ?? .white.opacity(0.5)
        let hovered = hoveredReminder == item.id
        return HStack(spacing: 8) {
            Button { onComplete(item.id) } label: {
                Image(systemName: hovered ? "checkmark.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(colour)
            }
            .buttonStyle(.plain)
            .onHover { hoveredReminder = $0 ? item.id : (hoveredReminder == item.id ? nil : hoveredReminder) }
            .help("Mark as done")
            Text(item.title).font(.caption).lineLimit(1)
            Spacer(minLength: 8)
            switch ReminderAgenda.label(item, now: now) {
            case .overdue: Text("Overdue").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            case .today: Text("Today").font(.caption2).foregroundStyle(.secondary)
            case .time(let date): Text(Self.time(date)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
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
