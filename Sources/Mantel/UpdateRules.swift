import Foundation

/// A release version, X.Y.Z, as the Release workflow tags it (vX.Y.Z).
struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        (self.major, self.minor, self.patch) = (major, minor, patch)
    }

    /// Accepts "1.2.0" or "v1.2.0" only, so a tag can safely be used in a file name or command.
    init?(tag: String) {
        let bare = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        self.init(major, minor, patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

enum UpdateRules {
    /// Only an installed copy updates itself; one built from source or run from Downloads is left alone.
    static func canSelfUpdate(appURL: URL, home: URL) -> Bool {
        let folder = appURL.deletingLastPathComponent().standardizedFileURL.path
        return folder == "/Applications" || folder == home.appendingPathComponent("Applications").standardizedFileURL.path
    }

    /// The GitHub command line tool, which can download from the private repo with the user's own login.
    /// Apps opened from Finder don't get the shell's PATH, so the usual install places are checked.
    static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    static func ghPath(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ghCandidates.first(where: exists)
    }

    /// The app's file name, and its release download.
    static let appName = "Mantel.app"
    static func zipName(_ version: AppVersion) -> String { "Mantel-\(version).zip" }
}
