import Foundation
import Testing
@testable import Mantel

/// A zipped Mantel.app with the given ID and version, ad-hoc signed, in a fresh temp folder.
private func zippedApp(id: String, version: String) throws -> (zip: URL, dir: URL) {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("notch-install-\(UUID().uuidString)")
    let app = dir.appendingPathComponent("src/Mantel.app/Contents")
    try fm.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("MacOS/Mantel"))
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version,
                                "CFBundleExecutable": "Notch", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Info.plist"))
    for (tool, args) in [("/usr/bin/codesign", ["--force", "--sign", "-", dir.appendingPathComponent("src/Mantel.app").path]),
                         ("/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.appendingPathComponent("src/Mantel.app").path,
                                             dir.appendingPathComponent("update.zip").path])] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
    }
    return (dir.appendingPathComponent("update.zip"), dir)
}

/// The "installed" copy: a minimal Notch bundle plus a marker file to show whether it was replaced.
private func target(in dir: URL) throws -> URL {
    let app = dir.appendingPathComponent("installed/Mantel.app")
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "local.mantel.app"], format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    try Data().write(to: app.appendingPathComponent("original"))
    return app
}

private func install(_ zip: URL, version: AppVersion, over app: URL, dir: URL) throws {
    let work = dir.appendingPathComponent("work-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    try UpdateService.installZip(zip, version: version, appURL: app, requirement: #"identifier "local.mantel.app""#,
                                 bundleID: "local.mantel.app", work: work)
}

@Test func refusesAnUpdateWhoseVersionDoesntMatchTheRelease() throws {
    let (zip, dir) = try zippedApp(id: "local.mantel.app", version: "1.0.0")
    let app = try target(in: dir)
    let error = #expect(throws: UpdateService.UpdateError.self) { try install(zip, version: AppVersion(2, 0, 0), over: app, dir: dir) }
    #expect(error?.message == "The download isn't the expected Mantel version")
    #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("original").path))
}

@Test func refusesADifferentApp() throws {
    let (zip, dir) = try zippedApp(id: "com.example.other", version: "2.0.0")
    let app = try target(in: dir)
    let error = #expect(throws: UpdateService.UpdateError.self) { try install(zip, version: AppVersion(2, 0, 0), over: app, dir: dir) }
    #expect(error?.message == "The download isn't the expected Mantel version")
    #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("original").path))
}

@Test func refusesWhenTheInstalledAppHasMoved() throws {
    let (zip, dir) = try zippedApp(id: "local.mantel.app", version: "2.0.0")
    let missing = dir.appendingPathComponent("installed/Mantel.app")   // never created
    let error = #expect(throws: UpdateService.UpdateError.self) { try install(zip, version: AppVersion(2, 0, 0), over: missing, dir: dir) }
    #expect(error?.message == "Mantel was moved or renamed; reopen it to update")
}

@Test func installsAMatchingUpdateWithOnlyItsOwnFiles() throws {
    let (zip, dir) = try zippedApp(id: "local.mantel.app", version: "2.0.0")
    let app = try target(in: dir)
    try install(zip, version: AppVersion(2, 0, 0), over: app, dir: dir)
    #expect(UpdateService.infoPlist(app)?["CFBundleShortVersionString"] as? String == "2.0.0")
    #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("original").path))
}
