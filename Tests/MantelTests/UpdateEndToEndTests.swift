import Foundation
import Testing
@testable import Mantel

/// Downloads the latest real release from the public repo and installs it over a throwaway copy,
/// never the real app. Only runs when asked:
///   MANTEL_UPDATE_E2E=1 swift test --filter UpdateEndToEnd
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MANTEL_UPDATE_E2E"] == "1"))
struct UpdateEndToEnd {
    static let releaseRequirement = #"identifier "local.mantel.app" and certificate leaf = H"e860aba5c846e315bae3f058b509d31c776ba0d7""#

    @Test func installsTheLatestRelease() async throws {
        let latest = try await UpdateService.latestVersion(session: UpdateService.session)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        let target = dir.appendingPathComponent(UpdateRules.appName)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.mantel.app"], format: .xml, options: 0)
            .write(to: target.appendingPathComponent("Contents/Info.plist"))

        try await UpdateService.install(latest, session: UpdateService.session, appURL: target,
                                        requirement: Self.releaseRequirement, bundleID: "local.mantel.app")

        #expect(UpdateService.infoPlist(target)?["CFBundleShortVersionString"] as? String == latest.description)
        #expect(UpdateVerifier.satisfies(target, requirement: Self.releaseRequirement))
    }
}

/// Installs a locally built, release-signed 9.9.9 zip over a throwaway copy:
///   MANTEL_UPDATE_FIXTURE_ZIP=/path/Mantel-9.9.9.zip swift test --filter UpdateInstallFixture
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MANTEL_UPDATE_FIXTURE_ZIP"] != nil))
struct UpdateInstallFixture {
    @Test func installsAReleaseSignedUpdate() throws {
        let zip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MANTEL_UPDATE_FIXTURE_ZIP"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        let target = dir.appendingPathComponent(UpdateRules.appName)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.mantel.app"], format: .xml, options: 0)
            .write(to: target.appendingPathComponent("Contents/Info.plist"))
        let work = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try UpdateService.installZip(zip, version: AppVersion(9, 9, 9), appURL: target,
                                     requirement: UpdateEndToEnd.releaseRequirement, bundleID: "local.mantel.app", work: work)

        #expect(UpdateService.infoPlist(target)?["CFBundleShortVersionString"] as? String == "9.9.9")
        #expect(UpdateVerifier.satisfies(target, requirement: UpdateEndToEnd.releaseRequirement))
    }
}
