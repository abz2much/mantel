/// The tabs of the panel that opens when you hover the notch.
enum HoverTab: CaseIterable {
    case music, clipboard, today

    /// The last tab you used; the first time, Music if a song is loaded, otherwise Today.
    static func opening(last: HoverTab?, hasTrack: Bool) -> HoverTab {
        last ?? (hasTrack ? .music : .today)
    }
}
