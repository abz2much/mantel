import Foundation
import Testing
@testable import Notch

@Test func readsAReleaseTag() {
    #expect(AppVersion(tag: "v1.2.0") == AppVersion(1, 2, 0))
    #expect(AppVersion(tag: "1.10.3") == AppVersion(1, 10, 3))
}

@Test func rejectsTagsThatArentVersions() {
    #expect(AppVersion(tag: "v1.2") == nil)
    #expect(AppVersion(tag: "v1.2.0-beta") == nil)
    #expect(AppVersion(tag: "../../evil") == nil)
    #expect(AppVersion(tag: "") == nil)
}

@Test func comparesVersionsNumerically() {
    #expect(AppVersion(1, 10, 0) > AppVersion(1, 9, 9))
    #expect(AppVersion(2, 0, 0) > AppVersion(1, 99, 99))
    #expect(!(AppVersion(1, 2, 0) > AppVersion(1, 2, 0)))
}

@Test func onlyUpdatesAnInstalledCopy() {
    let home = URL(fileURLWithPath: "/Users/someone")
    #expect(UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Applications/Notch.app"), home: home))
    #expect(UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Applications/Notch.app"), home: home))
    // A copy built from source, or run from Downloads, is left alone.
    #expect(!UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Dev/notch/build/Notch.app"), home: home))
    #expect(!UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Downloads/Notch.app"), home: home))
}

@Test func findsTheGitHubCommandLineTool() {
    let found = UpdateRules.ghPath(exists: { $0 == "/usr/local/bin/gh" })
    #expect(found == "/usr/local/bin/gh")
    #expect(UpdateRules.ghPath(exists: { _ in true }) == "/opt/homebrew/bin/gh")
    #expect(UpdateRules.ghPath(exists: { _ in false }) == nil)
}
