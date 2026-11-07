import Testing
@testable import Notch

@Test func anInstalledCopyTurnsOpenAtLoginOnTheFirstTime() {
    #expect(LoginItemRules.registerByDefault(alreadyDone: false, isInstalled: true))
}

@Test func openAtLoginDefaultIsAppliedOnlyOnce() {
    // If the user later turns it off, it stays off.
    #expect(!LoginItemRules.registerByDefault(alreadyDone: true, isInstalled: true))
}

@Test func aCopyBuiltFromSourceNeverAddsItself() {
    #expect(!LoginItemRules.registerByDefault(alreadyDone: false, isInstalled: false))
}

@Test func theMenuWarnsWhenCalendarAccessIsOff() {
    let warnings = MenuWarnings.make(calendarAccess: false, musicEnabled: true, blockedApps: [])
    #expect(warnings == [.calendarAccess])
}

@Test func theMenuWarnsWhichMusicAppIsBlocked() {
    let warnings = MenuWarnings.make(calendarAccess: true, musicEnabled: true, blockedApps: ["Spotify", "Music"])
    #expect(warnings == [.automation("Spotify and Music")])
}

@Test func blockedMusicIsntAWarningWhenTheMusicCardIsOff() {
    #expect(MenuWarnings.make(calendarAccess: true, musicEnabled: false, blockedApps: ["Spotify"]).isEmpty)
}

@Test func noWarningsWhenAllIsWell() {
    #expect(MenuWarnings.make(calendarAccess: true, musicEnabled: true, blockedApps: []).isEmpty)
}
