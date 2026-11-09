import AppKit
import Testing
@testable import Mantel

private let red = RGB(r: 0.9, g: 0.1, b: 0.1)
private let grey = RGB(r: 0.5, g: 0.5, b: 0.5)
private let darkBlue = RGB(r: 0.02, g: 0.05, b: 0.25)

@Test func accentPrefersVividColourOverMoreCommonGrey() {
    let pixels = Array(repeating: grey, count: 90) + Array(repeating: red, count: 10)
    let accent = ArtworkPalette.accent(fromPixels: pixels)
    #expect(accent.map { $0.r > 0.8 && $0.g < 0.3 && $0.b < 0.3 } == true)
}

@Test func accentIsNilForColourlessArtwork() {
    #expect(ArtworkPalette.accent(fromPixels: Array(repeating: grey, count: 100)) == nil)
}

@Test func accentIgnoresNearBlackPixels() {
    let nearBlackRed = RGB(r: 0.08, g: 0.0, b: 0.0)
    #expect(ArtworkPalette.accent(fromPixels: Array(repeating: nearBlackRed, count: 100)) == nil)
}

@Test func accentBrightensDarkColourSoItShowsOnBlack() {
    let accent = ArtworkPalette.accent(fromPixels: Array(repeating: darkBlue, count: 100))
    #expect(accent.map { max($0.r, $0.g, $0.b) >= 0.7 } == true)
    #expect(accent.map { $0.b > $0.r && $0.b > $0.g } == true)   // still blue
}

@Test func accentPicksTheLargerOfTwoVividColours() {
    let green = RGB(r: 0.1, g: 0.8, b: 0.2)
    let pixels = Array(repeating: red, count: 30) + Array(repeating: green, count: 70)
    let accent = ArtworkPalette.accent(fromPixels: pixels)
    #expect(accent.map { $0.g > $0.r } == true)
}

@Test func accentFromImageReadsItsPixels() {
    let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1).setFill()
        rect.fill()
        return true
    }
    let accent = ArtworkPalette.accent(from: image)
    #expect(accent.map { $0.b > 0.8 && $0.r < 0.3 } == true)
}
