import SwiftUI

struct NotchView: View {
    @ObservedObject var state: NotchState
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false

    private enum Urgency {
        case calm, soon, now
        var color: Color {
            switch self {
            case .calm: .white
            case .soon: .orange
            case .now: .red
            }
        }
    }

    private static func urgency(_ remaining: TimeInterval) -> Urgency {
        remaining > 60 ? .calm : remaining > 10 ? .soon : .now
    }

    var body: some View {
        if let event = state.event {
            TimelineView(.animation(minimumInterval: 0.05)) { context in
                let remaining = event.start.timeIntervalSince(context.date)
                let urgency = Self.urgency(remaining)
                HStack(spacing: 14) {
                    ring(remaining: remaining, urgency: urgency)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if let colour = event.calendarColor {
                                Circle().fill(Color(colour)).frame(width: 7, height: 7)
                            }
                            Text(Self.context(for: event))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.format(remaining))
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(urgency.color)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Self.seconds(remaining))
                        Text(remaining > 0 ? "STARTS IN" : "STARTED")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }

                    if let link = event.link {
                        joinButton(link: link, remaining: remaining, date: context.date)
                    }
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .help("Dismiss")
                }
                .frame(minWidth: 460)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    // Soft wash of the meeting's calendar colour, so work and personal meetings read differently.
                    RadialGradient(colors: [(event.calendarColor.map(Color.init) ?? .clear).opacity(0.22), .clear],
                                   center: .leading, startRadius: 0, endRadius: 280)
                }
                .environment(\.colorScheme, .dark)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: appeared)
                .onAppear { appeared = true }
                .onDisappear { appeared = false }
            }
        }
    }

    private func ring(remaining: TimeInterval, urgency: Urgency) -> some View {
        // Drains over the 5-minute lead-up; full red during the overrun.
        let progress = remaining <= 0 ? 1 : min(1, remaining / 300)
        return ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(urgency.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "video.fill")
                .font(.system(size: 14))
                .foregroundStyle(urgency.color)
        }
        .frame(width: 40, height: 40)
    }

    private func joinButton(link: MeetingLink, remaining: TimeInterval, date: Date) -> some View {
        // Pulse + glow once the meeting is about to start.
        let pulsing = remaining <= 10
        let wave = pulsing ? (sin(date.timeIntervalSinceReferenceDate * 2 * .pi * 1.4) + 1) / 2 : 0
        return Button("Join \(link.provider)") { onJoin(link.url) }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .scaleEffect(1 + 0.06 * wave)
            .shadow(color: .green.opacity(0.8 * wave), radius: 4 + 8 * wave)
    }

    private static func context(for event: MeetingEvent) -> String {
        var parts = [event.start.formatted(date: .omitted, time: .shortened), event.calendarTitle]
        if event.attendeeCount > 0 {
            parts.append("\(event.attendeeCount) \(event.attendeeCount == 1 ? "attendee" : "attendees")")
        }
        return parts.joined(separator: " · ")
    }

    private static func seconds(_ interval: TimeInterval) -> Int { Int(interval.rounded(.up)) }

    private static func format(_ interval: TimeInterval) -> String {
        let s = seconds(interval)
        if s <= 60 { return "\(s)s" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
