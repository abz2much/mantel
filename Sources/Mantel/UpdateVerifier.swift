import Foundation
import Security

/// Checks a downloaded update really comes from the same place as the running app,
/// by its code signature rather than by where it was downloaded from.
enum UpdateVerifier {
    /// Whether the code at `url` has a valid signature that meets `requirement` (code-signing requirement language).
    static func satisfies(_ url: URL, requirement: String) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }

    /// The running app's own designated requirement: its ID plus its signing certificate.
    /// An ad-hoc signed app (a local build) has none worth trusting, so it returns nil and never self-updates.
    static func ownRequirement() -> String? {
        var me: SecCode?
        var onDisk: SecStaticCode?
        var req: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &onDisk) == errSecSuccess, let onDisk,
              SecCodeCopyDesignatedRequirement(onDisk, [], &req) == errSecSuccess, let req,
              SecRequirementCopyString(req, [], &text) == errSecSuccess, let text
        else { return nil }
        let string = text as String
        return string.contains("certificate leaf") ? string : nil
    }
}
