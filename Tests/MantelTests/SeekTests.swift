import Testing
@testable import Mantel

@Test func seekTimeIsProportionalToClickPosition() {
    #expect(MusicCardView.seekTime(x: 50, width: 200, duration: 180) == 45)
}

@Test func seekTimeClampsBeforeStart() {
    #expect(MusicCardView.seekTime(x: -10, width: 200, duration: 180) == 0)
}

@Test func seekTimeClampsPastEnd() {
    #expect(MusicCardView.seekTime(x: 300, width: 200, duration: 180) == 180)
}

@Test func seekTimeIsZeroForZeroWidthBar() {
    #expect(MusicCardView.seekTime(x: 10, width: 0, duration: 180) == 0)
}
