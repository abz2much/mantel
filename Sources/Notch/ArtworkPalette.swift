import AppKit
import SwiftUI

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

/// Picks an accent colour from album art for the music card.
enum ArtworkPalette {
    private static let minBrightness = 0.15   // darker pixels carry no usable colour
    private static let minSaturation = 0.25   // greyer pixels aren't an accent
    private static let shownBrightness = 0.75 // floor so the accent is visible on the black notch
    private static let hueBins = 12

    /// `accent(fromPixels:)` for an image, sampled down to 24×24 so it's cheap on the main thread.
    static func accent(from image: NSImage) -> RGB? {
        let side = 24
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = stride(from: 0, to: data.count, by: 4).map { i in
            RGB(r: Double(data[i]) / 255, g: Double(data[i + 1]) / 255, b: Double(data[i + 2]) / 255)
        }
        return accent(fromPixels: pixels)
    }

    /// The artwork's dominant vivid colour, brightened to show on black; nil for colourless art.
    /// Groups pixels by hue, weighting each by saturation, so a vivid patch beats a larger dull area.
    static func accent(fromPixels pixels: [RGB]) -> RGB? {
        var weight = [Double](repeating: 0, count: hueBins)
        var sum = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: hueBins)
        for p in pixels {
            let maxC = max(p.r, p.g, p.b), minC = min(p.r, p.g, p.b)
            guard maxC >= minBrightness else { continue }
            let saturation = (maxC - minC) / maxC
            guard saturation >= minSaturation else { continue }
            let bin = min(hueBins - 1, Int(hue(p, maxC: maxC, minC: minC) * Double(hueBins)))
            weight[bin] += saturation
            sum[bin].r += p.r * saturation
            sum[bin].g += p.g * saturation
            sum[bin].b += p.b * saturation
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        var colour = RGB(r: sum[best].r / weight[best], g: sum[best].g / weight[best], b: sum[best].b / weight[best])
        let maxC = max(colour.r, colour.g, colour.b)
        if maxC < shownBrightness {
            let scale = shownBrightness / maxC   // keeps hue and saturation
            colour = RGB(r: colour.r * scale, g: colour.g * scale, b: colour.b * scale)
        }
        return colour
    }

    /// Hue in 0..<1.
    private static func hue(_ p: RGB, maxC: Double, minC: Double) -> Double {
        let d = maxC - minC
        guard d > 0 else { return 0 }
        var h: Double
        if maxC == p.r { h = (p.g - p.b) / d }
        else if maxC == p.g { h = (p.b - p.r) / d + 2 }
        else { h = (p.r - p.g) / d + 4 }
        h /= 6
        return h < 0 ? h + 1 : h
    }
}

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// A soft oval of colour that fades to nothing inside its own bounds, so it never shows a hard edge.
struct ColourWash: View {
    let colour: Color?
    /// Horizontal centre of the wash, measured from the leading edge of the view it sits behind.
    let centreX: CGFloat

    private static let size = CGSize(width: 260, height: 160)

    var body: some View {
        EllipticalGradient(colors: [(colour ?? .clear).opacity(0.28), .clear],
                           center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: Self.size.width, height: Self.size.height)
            .offset(x: centreX - Self.size.width / 2)
            .allowsHitTesting(false)
    }
}
