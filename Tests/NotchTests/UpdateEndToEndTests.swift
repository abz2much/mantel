import Foundation
import Testing
@testable import Notch

/// Downloads the latest real release with the `gh` login and installs it over a throwaway copy,
/// never the real app. Only runs when asked:
///   NOTCH_UPDATE_E2E=1 swift test --filter UpdateEndToEnd
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NOTCH_UPDATE_E2E"] == "1"))
struct UpdateEndToEnd {
    static let releaseRequirement = #"identifier "local.notch.app" and certificate leaf = H"19180d694e220d1d49ea3447a26528fcd16f1530""#

    @Test func installsTheLatestRelease() throws {
        let gh = try #require(UpdateRules.ghPath())
        let latest = try #require(Self.latestVersion(gh))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        let target = dir.appendingPathComponent(UpdateRules.appName)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.notch.app"], format: .xml, options: 0)
            .write(to: target.appendingPathComponent("Contents/Info.plist"))

        try UpdateService.install(latest, gh: gh, appURL: target, requirement: Self.releaseRequirement, bundleID: "local.notch.app")

        #expect(UpdateService.infoPlist(target)?["CFBundleShortVersionString"] as? String == latest.description)
        #expect(UpdateVerifier.satisfies(target, requirement: Self.releaseRequirement))
    }

    static func latestVersion(_ gh: String) -> AppVersion? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["api", "repos/abz2much/notch/releases/latest", "--jq", ".tag_name"]
        let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        let tag = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return AppVersion(tag: tag.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Installs a locally built, release-signed 9.9.9 zip over a throwaway copy:
///   NOTCH_UPDATE_FIXTURE_ZIP=/path/Mantel-9.9.9.zip swift test --filter UpdateInstallFixture
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NOTCH_UPDATE_FIXTURE_ZIP"] != nil))
struct UpdateInstallFixture {
    @Test func installsAReleaseSignedUpdate() throws {
        let zip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_UPDATE_FIXTURE_ZIP"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-e2e-\(UUID().uuidString)")
        let target = dir.appendingPathComponent(UpdateRules.appName)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.notch.app"], format: .xml, options: 0)
            .write(to: target.appendingPathComponent("Contents/Info.plist"))
        let work = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try UpdateService.installZip(zip, version: AppVersion(9, 9, 9), appURL: target,
                                     requirement: UpdateEndToEnd.releaseRequirement, bundleID: "local.notch.app", work: work)

        #expect(UpdateService.infoPlist(target)?["CFBundleShortVersionString"] as? String == "9.9.9")
        #expect(UpdateVerifier.satisfies(target, requirement: UpdateEndToEnd.releaseRequirement))
    }
}
