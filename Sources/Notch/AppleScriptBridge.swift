import Foundation

struct AppleScriptError: Error {
    let code: Int
}

/// Runs AppleScript off the main thread, one script at a time, so a slow or hung target app
/// can't block the UI. Scripts should carry their own `with timeout` block.
/// The only place NSAppleScript is used: swap the transport here (e.g. raw Apple Events) if ever needed.
final class AppleScriptBridge: @unchecked Sendable {   // `cache` is only touched on `queue`
    private let queue = DispatchQueue(label: "local.notch.app.applescript")
    private var cache: [String: NSAppleScript] = [:]

    /// Runs `source` and converts the reply with `parse`, both on the bridge's queue.
    /// Pass `cache: false` for one-off sources (e.g. ones with a value baked in) so the cache stays bounded.
    func run<T: Sendable>(_ source: String, cache: Bool = true, parse: @escaping @Sendable (NSAppleEventDescriptor) -> T) async -> Result<T, AppleScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source, cache: cache).map(parse))
            }
        }
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
