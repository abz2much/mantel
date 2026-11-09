import SwiftUI
import Testing
@testable import Mantel

@Test func flashOnlyWhenOpeningFromNothing() {
    #expect(NotchMotion.flashes(from: .hidden, to: .expanded))
    #expect(NotchMotion.flashes(from: .hidden, to: .compact))
    #expect(!NotchMotion.flashes(from: .compact, to: .expanded))
    #expect(!NotchMotion.flashes(from: .expanded, to: .compact))
    #expect(!NotchMotion.flashes(from: .expanded, to: .hidden))
}

@Test func radiiMatchSpec() {
    #expect(NotchMotion.radii(for: .compact) == (top: 6, bottom: 14))
    #expect(NotchMotion.radii(for: .expanded) == (top: 15, bottom: 20))
}

@Test func shapeFillsRectBottomAndInsetsTop() {
    let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
    let path = NotchShape(topRadius: 15, bottomRadius: 20).path(in: rect)
    #expect(path.boundingRect == rect)
    #expect(path.contains(CGPoint(x: 100, y: 99)))
    #expect(!path.contains(CGPoint(x: 2, y: 50)))
}
