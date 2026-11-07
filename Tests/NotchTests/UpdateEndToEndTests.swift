import Foundation
import Testing
@testable import Notch

/// Talks to GitHub with the real `gh` login, so it only runs when asked:
///   NOTCH_UPDATE_E2E=1 swift test --filter UpdateEndToEnd
/// It installs over a throwaway copy in a temp folder, never the real app.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NOTCH_UPDATE_E2E"] == "1"))
struct UpdateEndToEnd {
    @Test func refusesAReleaseWithoutTheReleaseCertificate() throws {
        let gh = try #require(UpdateRules.ghPath())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("Notch.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("original")
        try Data().write(to: marker)

        // 1.2.0 was released before releases were certificate-signed.
        let requirement = #"identifier "local.notch.app" and certificate leaf = H"19180d694e220d1d49ea3447a26528fcd16f1530""#
        let error = #expect(throws: UpdateService.UpdateError.self) {
            try UpdateService.install(AppVersion(1, 2, 0), gh: gh, appURL: target, requirement: requirement,
                                      bundleID: "local.notch.app")
        }
        #expect(error?.message == "The download isn't signed by Notch's release certificate")
        #expect(FileManager.default.fileExists(atPath: marker.path))   // left untouched
    }
}

/// Installs a locally built, release-signed zip over a throwaway copy:
///   NOTCH_UPDATE_FIXTURE_ZIP=/path/Notch-9.9.9.zip swift test --filter UpdateInstallFixture
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NOTCH_UPDATE_FIXTURE_ZIP"] != nil))
struct UpdateInstallFixture {
    @Test func installsAReleaseSignedUpdate() throws {
        let zip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_UPDATE_FIXTURE_ZIP"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        let target = dir.appendingPathComponent("Notch.app")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.notch.app"], format: .xml, options: 0)
            .write(to: target.appendingPathComponent("Contents/Info.plist"))
        let work = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let requirement = #"identifier "local.notch.app" and certificate leaf = H"19180d694e220d1d49ea3447a26528fcd16f1530""#

        try UpdateService.installZip(zip, version: AppVersion(9, 9, 9), appURL: target, requirement: requirement,
                                     bundleID: "local.notch.app", work: work)

        #expect(UpdateService.infoPlist(target)?["CFBundleShortVersionString"] as? String == "9.9.9")
        #expect(UpdateVerifier.satisfies(target, requirement: requirement))
    }
}
