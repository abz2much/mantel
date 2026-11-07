import AppKit
import os

/// Keeps an installed Notch up to date from the GitHub releases.
///
/// The repo is private, so downloads go through the GitHub command line tool (`gh`) and the user's own
/// login. A download is installed only if it's a newer version signed with the same certificate as the
/// running app. Files fetched by `gh` aren't marked as downloaded from the internet, so there's no
/// "Open Anyway" step, and the unchanged signature means macOS keeps Notch's permissions.
@MainActor
final class UpdateService: ObservableObject {
    enum Status: Equatable {
        case notChecked
        case checking
        case upToDate
        case installing(String)
        /// Updates can't run here; the reason is shown in the menu.
        case unavailable(String)
        case failed(String)
    }

    private static let log = Logger(subsystem: "local.notch.app", category: "update")
    private static let autoKey = "autoUpdate"
    nonisolated private static let repo = "abz2much/notch"
    private static let checkEvery: TimeInterval = 6 * 3600
    private static let firstCheckAfter: TimeInterval = 60

    @Published private(set) var status: Status = .notChecked
    @Published var autoInstall: Bool {
        didSet { UserDefaults.standard.set(autoInstall, forKey: Self.autoKey) }
    }

    let currentVersion: AppVersion?
    private var timer: Timer?
    private var busy = false

    init() {
        autoInstall = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
        currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init(tag:))
    }

    func start() {
        if let reason = blocker() { status = .unavailable(reason); return }
        let first = Timer(timeInterval: Self.firstCheckAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduledCheck() }
        }
        RunLoop.main.add(first, forMode: .common)
        let repeating = Timer(timeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduledCheck() }
        }
        RunLoop.main.add(repeating, forMode: .common)
        timer = repeating
    }

    /// From the menu: checks now and installs if there's an update, whatever the automatic setting.
    func checkNow() { check(install: true) }

    private func scheduledCheck() { check(install: autoInstall) }

    /// Why this copy can't update itself, if it can't.
    private func blocker() -> String? {
        if !UpdateRules.canSelfUpdate(appURL: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser) {
            return "Updates only work from Applications"
        }
        if UpdateVerifier.ownRequirement() == nil {
            return "This copy isn't a signed release; install the latest release once by hand"
        }
        if UpdateRules.ghPath() == nil {
            return "Updates need the GitHub CLI (gh)"
        }
        if currentVersion == nil { return "Unknown version" }
        return nil
    }

    private func check(install: Bool) {
        if let reason = blocker() { status = .unavailable(reason); return }
        guard !busy, let gh = UpdateRules.ghPath(), let current = currentVersion,
              let requirement = UpdateVerifier.ownRequirement() else { return }
        busy = true
        status = .checking
        let appURL = Bundle.main.bundleURL
        Task {
            let result = await Task.detached { () -> Result<AppVersion?, UpdateError> in
                do {
                    let tag = try Self.run(gh, ["api", "repos/\(Self.repo)/releases/latest", "--jq", ".tag_name"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let latest = AppVersion(tag: tag) else { throw UpdateError("Couldn't read the latest release") }
                    guard latest > current else { return .success(nil) }
                    guard install else { return .success(latest) }
                    try Self.install(latest, gh: gh, appURL: appURL, requirement: requirement)
                    return .success(latest)
                } catch let error as UpdateError {
                    return .failure(error)
                } catch {
                    return .failure(UpdateError("Update failed"))
                }
            }.value
            busy = false
            switch result {
            case .success(nil):
                status = .upToDate
            case .success(let version?) where install:
                status = .installing(version.description)
                Self.log.notice("Installed \(version.description, privacy: .public); relaunching")
                Self.relaunch(appURL)
            case .success(let version?):
                status = .failed("Notch \(version) is available: use Check for Updates")
            case .failure(let error):
                Self.log.error("Update check failed: \(error.message, privacy: .public)")
                status = .failed(error.message)
            }
        }
    }

    // MARK: Off the main thread

    struct UpdateError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// Downloads the release zip, unpacks it, checks it, and swaps it in for the running app.
    nonisolated static func install(_ version: AppVersion, gh: String, appURL: URL, requirement: String,
                                    bundleID: String? = Bundle.main.bundleIdentifier) throws {
        let fm = FileManager.default
        // A scratch folder on the same disk as the app, so the final swap is a quick rename.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        defer { try? fm.removeItem(at: work) }

        let zipName = "Notch-\(version).zip"
        _ = try run(gh, ["release", "download", "v\(version)", "--repo", repo, "--pattern", zipName, "--dir", work.path])
        try installZip(work.appendingPathComponent(zipName), version: version, appURL: appURL,
                       requirement: requirement, bundleID: bundleID, work: work)
    }

    /// Unpacks a release zip, checks it's the right app, version and signer, then swaps it in for `appURL`.
    nonisolated static func installZip(_ zip: URL, version: AppVersion, appURL: URL, requirement: String,
                                       bundleID: String?, work: URL) throws {
        let fm = FileManager.default
        let unpacked = work.appendingPathComponent("unpacked")
        _ = try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])

        let newApp = unpacked.appendingPathComponent("Notch.app")
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == bundleID,
              (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init(tag:)) == version
        else { throw UpdateError("The download isn't the expected Notch version") }
        guard UpdateVerifier.satisfies(newApp, requirement: requirement) else {
            throw UpdateError("The download isn't signed by Notch's release certificate")
        }
        _ = try fm.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
    }

    /// Runs a program with arguments (no shell) and returns what it printed; throws if it fails or hangs.
    nonisolated private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 120) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Stop it from outside if it hangs; reading below returns once it exits.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        if process.terminationReason == .uncaughtSignal { throw UpdateError("Timed out talking to GitHub") }
        guard process.terminationStatus == 0 else {
            throw UpdateError(path.hasSuffix("/gh") ? "GitHub CLI failed (signed in? run: gh auth status)" : "Couldn't unpack the update")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Opens the new copy once this one has quit.
    private static func relaunch(_ appURL: URL) {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The path is passed as an argument, never pasted into the command.
        opener.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", appURL.path]
        try? opener.run()
        NSApp.terminate(nil)
    }
}
