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
                case .clipboard: ClipboardListView(items: clipboard.items, enabled: clipboard.enabled, onCopy: clipboard.copy,
                                                   selection: state.clipboardSelection)
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
        .background {
            // Warm glow on every tab, except Music when the album art brings its own colour. It fades rather
            // than snapping, matching the music card's own colour wash.
            let showGlow = !(state.tab == .music && music.track != nil && music.accent != nil)
            MantelStyle.topGlow.padding(.horizontal, -20)   // starts below the notch, which stays black
                .opacity(showGlow ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: showGlow)
        }
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
        // Amber, or the album art's colour on the Music tab when there is one.
        let tint = (tab == .music ? music.accent : nil) ?? MantelStyle.amber
        return Button {
            state.tab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? tint.opacity(0.22) : .clear))
                .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var musicTab: some View {
        if !music.musicEnabled {
            EmptyMessage(text: "Music card is off", icon: "music.note")
        } else if music.track != nil {
            MusicCardView(music: music)
                .padding(.horizontal, -12)   // the card brings its own padding
        } else {
            EmptyMessage(text: "Nothing playing", icon: "music.note")
        }
    }
}

/// The Clipboard tab: recent copies, newest first. Click one to put it back on the clipboard.
struct ClipboardListView: View {
    let items: [ClipboardItem]
    let enabled: Bool
    let onCopy: (ClipboardItem) -> Void
    /// The row chosen with the arrow keys when opened with ⌃⌥V; rows then show their number (1–9).
    var selection: Int? = nil
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
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index, now: context.date).id(index)
                    }
                }
                if scrolls {
                    ScrollViewReader { proxy in
                        ScrollView { rows }.scrollIndicators(.automatic)   // about 7 rows show; more scroll
                            .onChange(of: selection) { _, row in
                                if let row { withAnimation(.snappy) { proxy.scrollTo(row) } }
                            }
                            .onAppear {
                                // Opened with ⌃⌥V: start at the top, whatever an earlier hover scrolled to.
                                if let selection { proxy.scrollTo(selection) }
                            }
                    }
                } else {
                    rows
                }
            }
        }
    }

    private func row(_ item: ClipboardItem, index: Int, now: Date) -> some View {
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
                if selection != nil {
                    Text(index < 9 ? "\(index + 1)" : "")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(MantelStyle.amber)
                        .frame(width: 10)
                }
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
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hoveredID == item.id || selection == index ? 0.1 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(MantelStyle.amber.opacity(selection == index ? 0.6 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .help("Copy again")
    }

    private func message(_ text: String, icon: String) -> some View {
        EmptyMessage(text: text, icon: icon)
    }
}
