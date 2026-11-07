import AppKit

struct AppleScriptError: Error {
    let code: Int
}

/// Runs AppleScript off the main thread, one script at a time, so a slow or hung target app
/// can't block the UI. Scripts should carry their own `with timeout` block.
/// The only place NSAppleScript is used: swap the transport here (e.g. raw Apple Events) if ever needed.
final class AppleScriptBridge: @unchecked Sendable {   // `cache` is only touched on `queue`
    private let queue = DispatchQueue(label: "local.notch.app.applescript")
    private var cache: [String: NSAppleScript] = [:]

    /// "Application isn't running", returned instead of sending when the target app has quit.
    static let notRunning = -600

    /// Runs `source` and converts the reply with `parse`, both on the bridge's queue.
    /// Pass `cache: false` for one-off sources (e.g. ones with a value baked in) so the cache stays bounded.
    /// With `onlyIfRunning`, the script is skipped unless that app is running at the moment it would be sent:
    /// a `tell` to an app that has quit would launch it again.
    func run<T: Sendable>(_ source: String, cache: Bool = true, onlyIfRunning bundleID: String? = nil,
                          parse: @escaping @Sendable (NSAppleEventDescriptor) -> T) async -> Result<T, AppleScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                if let bundleID, !Self.isRunning(bundleID) {
                    continuation.resume(returning: .failure(AppleScriptError(code: Self.notRunning)))
                    return
                }
                continuation.resume(returning: self.execute(source, cache: cache).map(parse))
            }
        }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    private func execute(_ source: String, cache useCache: Bool) -> Result<NSAppleEventDescriptor, AppleScriptError> {
        guard let script = cache[source] ?? NSAppleScript(source: source) else {
            return .failure(AppleScriptError(code: 0))
        }
        if useCache { cache[source] = script }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(AppleScriptError(code: error[NSAppleScript.errorNumber] as? Int ?? 0))
        }
        return .success(result)
    }
}
