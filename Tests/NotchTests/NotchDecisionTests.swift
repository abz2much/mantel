import Testing
@testable import Notch

@Test func batteryBeatsEverything() {
    let all = NotchInputs(hasReminder: true, musicShowsCard: true, screenHasNotch: true, hoverExpanded: true,
                          peeking: true, timerDoneShowing: true, batteryFlashing: true)
    #expect(NotchDecision.mode(for: all) == .battery)
}

@Test func meetingBeatsMusicAndHover() {
    let i = NotchInputs(hasReminder: true, musicShowsCard: true, screenHasNotch: true, hoverExpanded: true)
    #expect(NotchDecision.mode(for: i) == .meeting)
}

@Test func timeIsUpBeatsMusic() {
    let i = NotchInputs(musicShowsCard: true, screenHasNotch: true, timerDoneShowing: true)
    #expect(NotchDecision.mode(for: i) == .timerDone)
}

@Test func meetingBeatsTimeIsUp() {
    #expect(NotchDecision.mode(for: NotchInputs(hasReminder: true, timerDoneShowing: true)) == .meeting)
}

@Test func musicCompactOnNotch() {
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true, screenHasNotch: true)) == .musicCompact)
}

@Test func musicExpandedWhenHovered() {
    let i = NotchInputs(musicShowsCard: true, screenHasNotch: true, hoverExpanded: true)
    #expect(NotchDecision.mode(for: i) == .musicExpanded)
}

@Test func idleNotchWhenNothingPlays() {
    #expect(NotchDecision.mode(for: NotchInputs(screenHasNotch: true)) == .idle)
    #expect(NotchDecision.mode(for: NotchInputs(screenHasNotch: true, hoverExpanded: true)) == .idleExpanded)
}

@Test func peekWithoutNotch() {
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true, peeking: true)) == .musicExpanded)
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true)) == .hidden)
}

@Test func hiddenWithoutNotchOrMusic() {
    #expect(NotchDecision.mode(for: NotchInputs()) == .hidden)
}

@Test func hoverResetRules() {
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hasReminder: true, screenHasNotch: true, hoverExpanded: true)))
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(screenHasNotch: true, hoverExpanded: true, timerDoneShowing: true)))
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hoverExpanded: true)))
    #expect(NotchDecision.keepsHoverExpanded(NotchInputs(screenHasNotch: true, hoverExpanded: true)))
}
