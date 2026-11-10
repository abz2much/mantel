import Foundation
import Testing
@testable import Mantel

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
    #expect(UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Applications/Mantel.app"), home: home))
    #expect(UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Applications/Mantel.app"), home: home))
    // A copy built from source, or run from Downloads, is left alone.
    #expect(!UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Dev/notch/build/Mantel.app"), home: home))
    #expect(!UpdateRules.canSelfUpdate(appURL: URL(fileURLWithPath: "/Users/someone/Downloads/Mantel.app"), home: home))
}

@Test func publicReleaseURLs() {
    #expect(UpdateRules.latestReleaseURL.absoluteString == "https://api.github.com/repos/abz2much/mantel/releases/latest")
    #expect(UpdateRules.downloadURL(AppVersion(2, 1, 0)).absoluteString
            == "https://github.com/abz2much/mantel/releases/download/v2.1.0/Mantel-2.1.0.zip")
}

@Test func readsTagFromReleaseJSON() {
    #expect(UpdateRules.latestVersion(fromReleaseJSON: Data(#"{"tag_name":"v2.1.0","name":"x"}"#.utf8)) == AppVersion(2, 1, 0))
    #expect(UpdateRules.latestVersion(fromReleaseJSON: Data(#"{"name":"x"}"#.utf8)) == nil)
    #expect(UpdateRules.latestVersion(fromReleaseJSON: Data(#"{"tag_name":"v2.1.0-beta"}"#.utf8)) == nil)
    #expect(UpdateRules.latestVersion(fromReleaseJSON: Data(#"{"tag_name":2}"#.utf8)) == nil)
    #expect(UpdateRules.latestVersion(fromReleaseJSON: Data("<html>".utf8)) == nil)
}

@Test func httpMessagesForFailures() {
    #expect(UpdateRules.failureMessage(httpStatus: 200) == nil)
    #expect(UpdateRules.failureMessage(httpStatus: 404) == "No release found on GitHub")
    #expect(UpdateRules.failureMessage(httpStatus: 403) == "GitHub is busy, will try again later")
    #expect(UpdateRules.failureMessage(httpStatus: 429) == "GitHub is busy, will try again later")
    #expect(UpdateRules.failureMessage(httpStatus: 500) == "GitHub returned an error (500)")
    #expect(UpdateRules.failureMessage(urlError: URLError(.timedOut)) == "Timed out talking to GitHub")
    #expect(UpdateRules.failureMessage(urlError: URLError(.notConnectedToInternet)) == "Couldn't reach GitHub")
}


@Test func releaseDownloadsAreNamedMantel() {
    #expect(UpdateRules.zipName(AppVersion(1, 4, 0)) == "Mantel-1.4.0.zip")
    #expect(UpdateRules.appName == "Mantel.app")
}
