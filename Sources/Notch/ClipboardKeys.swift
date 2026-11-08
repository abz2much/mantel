/// Keys in the clipboard panel when it was opened with the shortcut: ↑ ↓ choose, Return copies,
/// 1–9 copy that item, Esc closes.
enum ClipboardKeys {
    enum Key: Equatable {
        case up, down, enter, escape
        case digit(Int)

        init?(keyCode: UInt16, characters: String?) {
            switch keyCode {
            case 126: self = .up
            case 125: self = .down
            case 36, 76: self = .enter
            case 53: self = .escape
            default:
                guard let c = characters, c.count == 1, let n = Int(c), (1...9).contains(n) else { return nil }
                self = .digit(n)
            }
        }
    }

    enum Result: Equatable {
        case select(Int)
        case copy(Int)
        case close
        /// Not ours: let the key through.
        case pass
    }

    /// On another tab (switched with the mouse), only Esc still works, so keys never copy a hidden item.
    static func handle(_ key: Key, selection: Int, count: Int, onClipboardTab: Bool = true) -> Result {
        guard onClipboardTab else { return key == .escape ? .close : .pass }
        switch key {
        case .escape: return .close
        case .enter: return count > 0 ? .copy(min(max(selection, 0), count - 1)) : .close
        case .up: return count > 0 ? .select(max(selection - 1, 0)) : .pass
        case .down: return count > 0 ? .select(min(selection + 1, count - 1)) : .pass
        case .digit(let n): return n <= count ? .copy(n - 1) : .pass
        }
    }
}
