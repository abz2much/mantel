import CoreGraphics
import Testing
@testable import Mantel

private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func notchFromAuxiliaryAreas() {
    let m = NotchGeometry.metrics(screenFrame: laptop, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
                                  leftAuxWidth: 650, rightAuxWidth: 650, topInset: 32)
    #expect(m.notchSize == CGSize(width: 212, height: 32))
    #expect(m.hasNotch)
}

@Test func noNotchWithoutAuxiliaryAreas() {
    let m = NotchGeometry.metrics(screenFrame: laptop, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 958),
                                  leftAuxWidth: nil, rightAuxWidth: nil, topInset: 0)
    #expect(!m.hasNotch)
    #expect(m.notchSize == CGSize(width: 0, height: 24))
}

@Test func menubarHeightFromVisibleFrame() {
    let m = NotchGeometry.metrics(screenFrame: laptop, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 958),
                                  leftAuxWidth: nil, rightAuxWidth: nil, topInset: 0)
    #expect(m.menubarHeight == 24)
}

@Test func windowIsTopCentreHalfScreen() {
    #expect(NotchGeometry.windowFrame(screenFrame: laptop) == CGRect(x: 378, y: 491, width: 756, height: 491))
}

@Test func windowOnSecondScreenUsesItsOrigin() {
    let monitor = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    #expect(NotchGeometry.windowFrame(screenFrame: monitor) == CGRect(x: 1992, y: 340, width: 960, height: 540))
}

@Test func compactOffsetCentresOverCamera() {
    #expect(NotchGeometry.compactOffset(leading: 40, trailing: 60) == 10)
    #expect(NotchGeometry.compactOffset(leading: 60, trailing: 40) == -10)
}

@Test func screenRectFlipsIntoScreenCoordinates() {
    let r = NotchGeometry.screenRect(windowRect: CGRect(x: 161, y: 0, width: 434, height: 220),
                                     windowFrame: CGRect(x: 378, y: 491, width: 756, height: 491))
    #expect(r == CGRect(x: 539, y: 762, width: 434, height: 220))
}

@Test func hoverZoneIsTopCentreStrip() {
    #expect(NotchGeometry.hoverZone(screenFrame: CGRect(x: 1512, y: -200, width: 1920, height: 1080))
            == CGRect(x: 2240, y: 877, width: 464, height: 4))
}

@Test func flipFromWindowListCoordinates() {
    #expect(ActiveScreen.flip(cgBounds: CGRect(x: 100, y: 50, width: 800, height: 600), primaryHeight: 982)
            == CGRect(x: 100, y: 332, width: 800, height: 600))
}

private let twoScreens: [(id: Int, frame: CGRect)] = [
    (1, CGRect(x: 0, y: 0, width: 1512, height: 982)),
    (2, CGRect(x: 1512, y: -200, width: 1920, height: 1080)),
]

@Test func activeScreenFromWindow() {
    #expect(ActiveScreen.pick(windowBounds: CGRect(x: 1600, y: 100, width: 800, height: 600),
                              mouse: .zero, screens: twoScreens) == 2)
}

@Test func straddlingWindowPicksLargerShare() {
    #expect(ActiveScreen.pick(windowBounds: CGRect(x: 1300, y: 100, width: 600, height: 400),
                              mouse: .zero, screens: twoScreens) == 2)
}

@Test func activeScreenFallsBackToMouse() {
    #expect(ActiveScreen.pick(windowBounds: nil, mouse: CGPoint(x: 200, y: 300), screens: twoScreens) == 1)
}

@Test func hoverZoneIncludesTheTopEdge() {
    let frame = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    #expect(NotchGeometry.hoverZone(screenFrame: frame).contains(CGPoint(x: frame.midX, y: frame.maxY)))
}
