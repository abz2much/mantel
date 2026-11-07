import Testing
@testable import Notch

@Test func batteryBeatsEverything() {
    let all = NotchInputs(hasReminder: true, musicShowsCard: true, screenHasNotch: true, hoverExpanded: true,
                          timerDoneShowing: true, batteryFlashing: true, timerRunning: true)
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

@Test func musicOnMonitorShowsTab() {
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true)) == .tab)
}

@Test func hiddenWithoutNotchOrMusic() {
    #expect(NotchDecision.mode(for: NotchInputs()) == .hidden)
}

@Test func hoverResetRules() {
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hasReminder: true, screenHasNotch: true, hoverExpanded: true)))
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(screenHasNotch: true, hoverExpanded: true, timerDoneShowing: true)))
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hoverExpanded: true, monitorsEnabled: false)))
    #expect(NotchDecision.keepsHoverExpanded(NotchInputs(hoverExpanded: true)))   // a monitor can be hovered
    #expect(NotchDecision.keepsHoverExpanded(NotchInputs(screenHasNotch: true, hoverExpanded: true)))
}

@Test func monitorRestsAsTabWhileMusicPlays() {
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true)) == .tab)
    #expect(NotchDecision.mode(for: NotchInputs(timerRunning: true)) == .tab)
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true, tabEnabled: false)) == .hidden)
    #expect(NotchDecision.mode(for: NotchInputs()) == .hidden)
}

@Test func monitorHoverOpensPanel() {
    #expect(NotchDecision.mode(for: NotchInputs(hoverExpanded: true)) == .idleExpanded)
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true, hoverExpanded: true)) == .musicExpanded)
}

@Test func alertsOnlyOnAlertScreen() {
    #expect(NotchDecision.mode(for: NotchInputs(hasReminder: true, screenHasNotch: true, isAlertScreen: false)) == .idle)
    #expect(NotchDecision.mode(for: NotchInputs(hasReminder: true, musicShowsCard: true, isAlertScreen: false)) == .tab)
}

@Test func monitorsOffHidesEverythingButLidClosedMeetings() {
    #expect(NotchDecision.mode(for: NotchInputs(musicShowsCard: true, monitorsEnabled: false)) == .hidden)
    #expect(NotchDecision.mode(for: NotchInputs(hasReminder: true, monitorsEnabled: false, anyNotchScreen: true)) == .hidden)
    #expect(NotchDecision.mode(for: NotchInputs(hasReminder: true, monitorsEnabled: false, anyNotchScreen: false)) == .meeting)
    #expect(NotchDecision.mode(for: NotchInputs(timerDoneShowing: true, monitorsEnabled: false, anyNotchScreen: false)) == .hidden)
}

@Test func batteryOnMonitorShowsEvenWithTabOff() {
    #expect(NotchDecision.mode(for: NotchInputs(batteryFlashing: true, tabEnabled: false)) == .battery)
}

@Test func alertsGoToOneScreenOnly() {
    let screens = [ScreenInfo(id: 1, hasNotch: true, isMain: true),
                   ScreenInfo(id: 2, hasNotch: false, isMain: false),
                   ScreenInfo(id: 3, hasNotch: false, isMain: false)]
    #expect(NotchDecision.alertScreen(screens: screens, active: 3, monitorsEnabled: true) == 3)
    #expect(NotchDecision.alertScreen(screens: screens, active: 3, monitorsEnabled: false) == 1)
    #expect(NotchDecision.alertScreen(screens: screens, active: nil, monitorsEnabled: true) == 1)
    let monitorsOnly = [ScreenInfo(id: 2, hasNotch: false, isMain: true), ScreenInfo(id: 3, hasNotch: false, isMain: false)]
    #expect(NotchDecision.alertScreen(screens: monitorsOnly, active: 3, monitorsEnabled: false) == 2)
    #expect(NotchDecision.alertScreen(screens: [], active: nil, monitorsEnabled: true) == nil)
}

@Test func alertsCloseHoverOnEveryScreen() {
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hasReminder: true, hoverExpanded: true, isAlertScreen: false)))
    #expect(!NotchDecision.keepsHoverExpanded(NotchInputs(hoverExpanded: true, isAlertScreen: false, timerDoneShowing: true)))
}
