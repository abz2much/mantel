import Foundation
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

@Test func theDefaultCountsAsDoneOnceItTookEffect() {
    #expect(LoginItemRules.defaultIsDone(afterAttempt: .enabled))
    #expect(LoginItemRules.defaultIsDone(afterAttempt: .needsApproval))
}

@Test func aFailedFirstAttemptIsTriedAgainNextLaunch() {
    #expect(!LoginItemRules.defaultIsDone(afterAttempt: .notRegistered))
}

@Test func theUpdateLineSaysWhenANewVersionIsAvailable() {
    #expect(UpdateStatusText.line(version: AppVersion(1, 5, 0), status: .available("1.6.0")) == "Mantel 1.6.0 is available")
    #expect(UpdateStatusText.line(version: AppVersion(1, 5, 0), status: .upToDate) == "Mantel 1.5.0: up to date")
}

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID())")! }

@MainActor
@Test func monitorSettingsDefaultOn() {
    let m = MonitorSettings(defaults: freshDefaults())
    #expect(m.enabled)
    #expect(m.tabEnabled)
    #expect(m.showsTab)
}

@MainActor
@Test func monitorSettingsPersist() {
    let d = freshDefaults()
    let m = MonitorSettings(defaults: d)
    m.enabled = false
    m.tabEnabled = false
    let again = MonitorSettings(defaults: d)
    #expect(!again.enabled)
    #expect(!again.tabEnabled)
}

@MainActor
@Test func tabHiddenWhenMonitorsOff() {
    let m = MonitorSettings(defaults: freshDefaults())
    m.enabled = false
    #expect(m.tabEnabled)
    #expect(!m.showsTab)
}
