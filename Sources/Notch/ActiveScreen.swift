import AppKit

/// Finds the screen of the app in front, from its front window's bounds. Window bounds and owner need
/// no permission; window names would need Screen Recording, so they're never read.
enum ActiveScreen {
    /// The screen holding most of the window; without a window, the screen with the pointer.
    static func pick(windowBounds: CGRect?, mouse: CGPoint, screens: [(id: Int, frame: CGRect)]) -> Int? {
        if let windowBounds {
            let best = screens
                .map { (id: $0.id, area: area($0.frame.intersection(windowBounds))) }
                .max { $0.area < $1.area }
            if let best, best.area > 0 { return best.id }
        }
        return screens.first { NSMouseInRect(mouse, $0.frame, false) }?.id
    }

    /// The window list uses a top-left origin on the primary screen; AppKit uses bottom-left.
    static func flip(cgBounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cgBounds.minX, y: primaryHeight - cgBounds.maxY, width: cgBounds.width, height: cgBounds.height)
    }

    @MainActor
    static func current() -> Int? {
        let screens = NSScreen.screens.compactMap { s in s.screenNumber.map { (id: $0.intValue, frame: s.frame) } }
        guard let primary = NSScreen.screens.first else { return nil }
        return pick(windowBounds: frontWindowBounds(primaryHeight: primary.frame.height),
                    mouse: NSEvent.mouseLocation, screens: screens)
    }

    private static func frontWindowBounds(primaryHeight: CGFloat) -> CGRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            return flip(cgBounds: bounds, primaryHeight: primaryHeight)
        }
        return nil
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
