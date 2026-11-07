import SwiftUI

/// Mantel's look: warm amber firelight, the colour of the app icon.
enum MantelStyle {
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.36)
    static let amberDeep = Color(red: 0.94, green: 0.48, blue: 0.16)
    static let glow = Color(red: 1.0, green: 0.59, blue: 0.24)

    /// The glow from the top of the hover panel, like firelight under a mantel. Placed below the notch
    /// strip, so the very top stays black and the panel still blends into the real notch.
    static var topGlow: some View {
        EllipticalGradient(
            stops: [.init(color: glow.opacity(0.42), location: 0),
                    .init(color: glow.opacity(0.12), location: 0.45),
                    .init(color: .clear, location: 1)],
            center: .init(x: 0.5, y: 0.12),
            startRadiusFraction: 0, endRadiusFraction: 0.75
        )
        // Fades in from black at the top edge, so there's no hard line under the notch.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

/// A centred "nothing here yet" message with an amber icon, used on every tab.
struct EmptyMessage: View {
    let text: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(MantelStyle.amber)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
