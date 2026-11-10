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

    /// The app's file name, and its release download.
    static let appName = "Mantel.app"
    static func zipName(_ version: AppVersion) -> String { "Mantel-\(version).zip" }

    /// The public GitHub repo the releases come from. No login is needed to read them.
    static let repo = "abz2much/mantel"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    static func downloadURL(_ version: AppVersion) -> URL {
        URL(string: "https://github.com/\(repo)/releases/download/v\(version)/\(zipName(version))")!
    }

    /// The version in GitHub's latest-release reply, if it's a plain X.Y.Z tag.
    static func latestVersion(fromReleaseJSON data: Data) -> AppVersion? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else { return nil }
        return AppVersion(tag: tag)
    }

    /// What to show for a reply from GitHub that isn't a success; nil when it is.
    static func failureMessage(httpStatus: Int) -> String? {
        switch httpStatus {
        case 200: return nil
        case 404: return "No release found on GitHub"
        case 403, 429: return "GitHub is busy, will try again later"
        default: return "GitHub returned an error (\(httpStatus))"
        }
    }

    static func failureMessage(urlError: URLError) -> String {
        urlError.code == .timedOut ? "Timed out talking to GitHub" : "Couldn't reach GitHub"
    }
}
