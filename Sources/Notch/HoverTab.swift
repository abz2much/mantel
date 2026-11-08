/// The tabs of the panel that opens when you hover the notch, in the order they appear.
enum HoverTab: CaseIterable {
    case today, clipboard, timer, music

    var title: String {
        switch self {
        case .today: "Today"
        case .clipboard: "Clipboard"
        case .timer: "Timer"
        case .music: "Music"
        }
    }

    var icon: String {
        switch self {
        case .today: "calendar"
        case .clipboard: "doc.on.clipboard"
        case .timer: "timer"
        case .music: "music.note"
        }
    }

    /// The last tab you used; the first time, Music if a song is loaded, otherwise Today.
    static func opening(last: HoverTab?, hasTrack: Bool) -> HoverTab {
        last ?? (hasTrack ? .music : .today)
    }
}
