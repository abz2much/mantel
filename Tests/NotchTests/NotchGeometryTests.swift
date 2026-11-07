import CoreGraphics
import Testing
@testable import Notch

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
