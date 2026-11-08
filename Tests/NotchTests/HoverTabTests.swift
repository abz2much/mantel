import Testing
@testable import Notch

@Test func opensTheLastTabUsed() {
    #expect(HoverTab.opening(last: .clipboard, hasTrack: true) == .clipboard)
    #expect(HoverTab.opening(last: .today, hasTrack: true) == .today)
}

@Test func firstTimeOpensMusicWhenSomethingIsLoaded() {
    #expect(HoverTab.opening(last: nil, hasTrack: true) == .music)
}

@Test func firstTimeOpensTodayWhenNothingIsLoaded() {
    #expect(HoverTab.opening(last: nil, hasTrack: false) == .today)
}

@Test func tabsAreInTheChosenOrder() {
    #expect(HoverTab.allCases == [.today, .clipboard, .timer, .music])
    #expect(HoverTab.allCases.map(\.title) == ["Today", "Clipboard", "Timer", "Music"])
}
