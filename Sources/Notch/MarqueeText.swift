import SwiftUI

/// One line of text that slowly scrolls when it's too long to fit, instead of being cut off with "…".
/// Pauses at the start of each loop; text that fits stays still.
struct MarqueeText: View {
    let text: String
    let font: Font

    private static let gap: CGFloat = 40         // space before the repeated copy
    private static let speed: CGFloat = 30       // points per second
    private static let pause: TimeInterval = 2   // rest at the start of each loop

    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        // A hidden one-line copy gives the view its height and the width it's allowed.
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let overflows = textWidth > geo.size.width
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !overflows)) { context in
                        HStack(spacing: Self.gap) {
                            label
                            if overflows { label }
                        }
                        .offset(x: overflows ? offset(at: context.date) : 0)
                    }
                    .mask {
                        if overflows {
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                                   .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.black
                        }
                    }
                }
            }
            .clipped()
            .onChange(of: text) { start = Date() }
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { textWidth = g.size.width }
                        .onChange(of: g.size.width) { textWidth = g.size.width }
                }
            }
    }

    /// Scrolls one text-width plus gap, so the repeated copy lands exactly where the first began.
    private func offset(at date: Date) -> CGFloat {
        let distance = textWidth + Self.gap
        let cycle = Self.pause + Double(distance / Self.speed)
        let phase = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        return phase < Self.pause ? 0 : -CGFloat(phase - Self.pause) * Self.speed
    }
}
