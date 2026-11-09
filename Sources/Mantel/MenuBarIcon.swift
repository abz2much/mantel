import AppKit

/// Mantel's menu bar icon: the notch (outlined, with its glow dot) resting on a shelf.
/// A template image, so macOS draws it black or white to suit the menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            NSColor.black.set()
            // The notch: an outlined pill.
            let pill = NSBezierPath(roundedRect: NSRect(x: 5.2, y: 2.7, width: 11.6, height: 5.6), xRadius: 2.8, yRadius: 2.8)
            pill.lineWidth = 1.5
            pill.stroke()
            // Its glow dot.
            NSBezierPath(ovalIn: NSRect(x: 7.1, y: 4.3, width: 2.4, height: 2.4)).fill()
            // The shelf.
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 10.5, width: 19, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mantel"
        return image
    }()
}
