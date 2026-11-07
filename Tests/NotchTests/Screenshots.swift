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
        let view = IdlePanelView(events: events, calendarAccess: true, music: playingMusic(), onJoin: { _ in })
        try save(notchShape(view), as: "idle-panel.png")
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
