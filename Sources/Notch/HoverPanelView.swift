import SwiftUI

/// What opens when you hover the notch: Music, Clipboard, Today and Timer tabs.
/// All four tabs always show, in the same places, and the panel keeps one size on every tab.
struct HoverPanelView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var music: MusicService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var timer: TimerService
    let onJoin: (URL) -> Void

    /// Fits the music card, five meetings, or about seven copies (the list scrolls for more).
    static let contentHeight: CGFloat = 180
    static let width: CGFloat = 404

    var body: some View {
        VStack(spacing: 8) {
            tabBar
            Group {
                switch state.tab {
                case .music: musicTab
                case .clipboard: ClipboardListView(items: clipboard.items, enabled: clipboard.enabled, onCopy: clipboard.copy)
                case .today: TodayView(events: calendar.events, calendarAccess: calendar.hasAccess, onJoin: onJoin)
                case .timer: TimerTabView(timer: timer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(width: Self.width, height: Self.contentHeight + 40, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.music, "Music", "music.note")
            tabButton(.clipboard, "Clipboard", "doc.on.clipboard")
            tabButton(.today, "Today", "calendar")
            tabButton(.timer, "Timer", "timer")
            Spacer()
        }
    }

    private func tabButton(_ tab: HoverTab, _ title: String, _ icon: String) -> some View {
        let selected = state.tab == tab
        return Button {
            state.tab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? .white.opacity(0.16) : .clear))
                .foregroundStyle(selected ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var musicTab: some View {
        if !music.musicEnabled {
            Label("Music card is off", systemImage: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if music.track != nil {
            MusicCardView(music: music)
                .padding(.horizontal, -12)   // the card brings its own padding
        } else {
            Label("Nothing playing", systemImage: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The Clipboard tab: recent copies, newest first. Click one to put it back on the clipboard.
struct ClipboardListView: View {
    let items: [ClipboardItem]
    let enabled: Bool
    let onCopy: (ClipboardItem) -> Void
    /// Off only for screenshots: SwiftUI's image renderer can't draw scroll views.
    var scrolls = true
    @State private var copiedText: String?
    @State private var hoveredID: UUID?

    var body: some View {
        if !enabled {
            message("Clipboard history is off", icon: "doc.on.clipboard")
        } else if items.isEmpty {
            message("Copy some text and it shows up here", icon: "doc.on.clipboard")
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let rows = VStack(spacing: 2) {
                    ForEach(items) { row($0, now: context.date) }
                }
                if scrolls {
                    ScrollView { rows }.scrollIndicators(.automatic)   // about 7 rows show; more scroll
                } else {
                    rows
                }
            }
        }
    }

    private func row(_ item: ClipboardItem, now: Date) -> some View {
        // Matched by text: copying moves the item to the top as a new row.
        let copied = copiedText == item.text
        return Button {
            hoveredID = nil   // the pointer is now over a different row
            withAnimation(.snappy) {
                onCopy(item)
                copiedText = item.text
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedText == item.text { withAnimation(.snappy) { copiedText = nil } }
            }
        } label: {
            HStack(spacing: 8) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    Text(ClipboardItem.age(from: item.copiedAt, to: now))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hoveredID == item.id ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .help("Copy again")
    }

    private func message(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
