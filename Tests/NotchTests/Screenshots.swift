import AppKit
import SwiftUI
import Testing
@testable import Notch

/// Renders README screenshots with made-up data. Skipped unless asked for:
///   NOTCH_FAKE_SPOTIFY=1 NOTCH_SCREENSHOTS_DIR=docs/images swift test --filter Screenshots
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NOTCH_SCREENSHOTS_DIR"] != nil))
struct Screenshots {
    private let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_SCREENSHOTS_DIR"] ?? ".")

    @Test func musicCard() throws {
        let music = playingMusic()
        try save(notchShape(MusicCardView(music: music)), as: "music-card.png")
    }

    @Test func compact() throws {
        let music = playingMusic()
        let view = HStack(spacing: 0) {
            MusicCompactLeading(music: music).frame(width: 40)
            Color.black.frame(width: 190)   // the notch itself
            MusicCompactTrailing(music: music).frame(width: 40)
        }
        .frame(height: 32)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(.black))
        .environment(\.colorScheme, .dark)
        .padding(24)
        try save(view, as: "compact.png")
    }

    @Test func meeting() throws {
        let state = NotchState()
        state.event = MeetingEvent(
            id: "demo", title: "Design review", start: Date().addingTimeInterval(42),
            end: Date().addingTimeInterval(42 + 1800),
            link: MeetingLink(url: URL(string: "https://zoom.us/j/123456789")!, source: .location, provider: "Zoom"),
            calendarTitle: "Work", attendeeCount: 6, isDeclined: false,
            calendarColor: RGB(r: 0.25, g: 0.55, b: 1.0))
        state.content = .meeting
        try save(notchShape(NotchView(state: state, onJoin: { _ in }, onDismiss: {})), as: "meeting.png")
    }

    @Test func idlePanel() throws {
        func meeting(_ title: String, in minutes: Double, lasts: Double = 30, colour: RGB, zoom: Bool = false) -> MeetingEvent {
            let start = Date().addingTimeInterval(minutes * 60)
            return MeetingEvent(
                id: title, title: title, start: start, end: start.addingTimeInterval(lasts * 60),
                link: zoom ? MeetingLink(url: URL(string: "https://zoom.us/j/123456789")!, source: .location, provider: "Zoom") : nil,
                calendarTitle: "Work", attendeeCount: 4, isDeclined: false, calendarColor: colour)
        }
        let work = RGB(r: 0.25, g: 0.55, b: 1.0), personal = RGB(r: 0.3, g: 0.8, b: 0.4)
        let events = [
            meeting("Team standup", in: -10, colour: work, zoom: true),
            meeting("Design review", in: 80, colour: work, zoom: true),
            meeting("Lunch with Sam", in: 150, lasts: 60, colour: personal),
            meeting("1:1", in: 240, colour: work),
        ]
        let view = panel(.today, events: events)
        try save(notchShape(view), as: "idle-panel.png")

        func reminder(_ title: String, in minutes: Double, colour: RGB) -> ReminderItem {
            ReminderItem(id: title, title: title, due: Date().addingTimeInterval(minutes * 60), hasTime: true, listColor: colour)
        }
        let orange = RGB(r: 1, g: 0.6, b: 0.2)
        let due = [reminder("Send the invoice", in: -90, colour: orange),
                   reminder("Call the dentist", in: 45, colour: personal),
                   reminder("Book train tickets", in: 200, colour: orange)]
        try save(notchShape(panel(.today, events: events, reminders: due)), as: "today-reminders.png")
        // Three meeting rows (no "+more" line): the tightest fit with reminders.
        try save(notchShape(panel(.today, events: Array(events.prefix(3)), reminders: due)), as: "today-reminders-3.png")
    }

    @Test func clipboard() throws {
        let now = Date()
        let items = [
            ClipboardItem(text: "https://example.com/docs/getting-started", copiedAt: now.addingTimeInterval(-60)),
            ClipboardItem(text: "Meeting moved to Thursday 3pm", copiedAt: now.addingTimeInterval(-4 * 60)),
            ClipboardItem(text: "git checkout -b feature/clipboard", copiedAt: now.addingTimeInterval(-9 * 60)),
            ClipboardItem(text: "Order #A-1042", copiedAt: now.addingTimeInterval(-15 * 60)),
        ]
        let view = VStack(spacing: 8) {
            tabs(selected: "Clipboard")
            ClipboardListView(items: items, enabled: true, onCopy: { _ in }, scrolls: false)
                .frame(height: HoverPanelView.contentHeight, alignment: .top)
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
        .frame(width: HoverPanelView.width)
        .background { MantelStyle.topGlow.padding(.horizontal, -20) }
        .environment(\.colorScheme, .dark)
        try save(notchShape(view), as: "clipboard.png")
    }

    @Test func musicTab() throws {
        let state = NotchState()
        state.tab = .music
        let view = HoverPanelView(state: state, music: playingMusic(), calendar: CalendarService(), reminders: RemindersService(),
                                  clipboard: ClipboardService(), timer: TimerService(), onJoin: { _ in })
        try save(notchShape(view), as: "music-tab.png")
    }

    @Test func timerTab() throws {
        let state = NotchState()
        state.tab = .timer
        let timer = TimerService()
        func panel() -> some View {
            HoverPanelView(state: state, music: MusicService(), calendar: CalendarService(), reminders: RemindersService(),
                           clipboard: ClipboardService(), timer: timer, onJoin: { _ in })
        }
        try save(notchShape(panel()), as: "timer-start.png")
        timer.start(minutes: 25)
        try save(notchShape(panel()), as: "timer-running.png")
        timer.stop()
        // A finished focus session, so the popup shows its break button.
        var clock = Date()
        let finished = TimerService(now: { clock }, chime: {})
        finished.start(minutes: 25)
        clock = clock.addingTimeInterval(25 * 60)
        finished.checkFinished()
        try save(notchShape(TimerDoneView(timer: finished)), as: "timer-done.png")
    }

    /// The hover panel on one tab, with calendar data that doesn't come from the real calendar.
    private func panel(_ tab: HoverTab, events: [MeetingEvent], reminders: [ReminderItem] = []) -> some View {
        VStack(spacing: 8) {
            tabs(selected: tab == .today ? "Today" : "Music")
            TodayView(events: events, calendarAccess: true, onJoin: { _ in }, reminders: reminders,
                      remindersOn: !reminders.isEmpty)
                .frame(height: HoverPanelView.contentHeight, alignment: .top)
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
        .frame(width: HoverPanelView.width)
        .background { MantelStyle.topGlow.padding(.horizontal, -20) }
        .environment(\.colorScheme, .dark)
    }

    /// A stand-in for the panel's tab bar (the real one needs live services).
    private func tabs(selected: String) -> some View {
        HStack(spacing: 4) {
            ForEach(HoverTab.allCases.map { ($0.title, $0.icon) }, id: \.0) { title, icon in
                Label(title, systemImage: icon)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(title == selected ? MantelStyle.amber.opacity(0.22) : .clear))
                    .foregroundStyle(title == selected ? AnyShapeStyle(MantelStyle.amber) : AnyShapeStyle(.secondary))
            }
            Spacer()
        }
    }

    private func playingMusic() -> MusicService {
        let music = MusicService()
        music.showAlbumArt = true
        music.refresh()
        music.seek(to: 84)
        return music
    }

    /// Black notch-like backing (square top, rounded bottom), masked like the real notch.
    private func notchShape(_ content: some View) -> some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 34)   // room the real notch leaves at the top
            .padding(.bottom, 14)
            .background(.black)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))   // as DynamicNotchKit masks it
            .padding(24)
    }

    private func save(_ view: some View, as name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent(name))
    }
}
