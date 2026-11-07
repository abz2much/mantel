import SwiftUI

enum NotchPresentation: Equatable { case hidden, compact, expanded }

/// "E · Snap with a flash": quick, no bounce, no blur, with an amber flash when opening from nothing.
enum NotchMotion {
    static let openDuration: TimeInterval = 0.22
    static let closeDuration: TimeInterval = 0.17
    /// The flash peaks within the first 15% of the opening.
    static let flashLead: TimeInterval = 0.033

    static let open = Animation.timingCurve(0.2, 0, 0, 1, duration: openDuration)
    static let close = Animation.timingCurve(0.4, 0, 1, 1, duration: closeDuration)

    /// Only opening from nothing flashes, so moving between the side pieces and the panel doesn't flicker.
    static func flashes(from: NotchPresentation, to: NotchPresentation) -> Bool {
        from == .hidden && to != .hidden
    }

    static func radii(for presentation: NotchPresentation) -> (top: CGFloat, bottom: CGFloat) {
        presentation == .expanded ? (15, 20) : (6, 14)
    }
}
