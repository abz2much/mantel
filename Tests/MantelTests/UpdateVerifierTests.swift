import Foundation
import Testing
@testable import Mantel

/// A tiny signed program in a temp folder, standing in for a downloaded app.
private func signedTool(identifier: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notch-verify-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tool = dir.appendingPathComponent("tool")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: tool)
    let sign = Process()
    sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    sign.arguments = ["--force", "--sign", "-", "--identifier", identifier, tool.path]
    sign.standardError = FileHandle.nullDevice
    try sign.run(); sign.waitUntilExit()
    return tool
}

@Test func acceptsCodeThatMeetsTheRequirement() throws {
    let tool = try signedTool(identifier: "com.example.notch-test")
    #expect(UpdateVerifier.satisfies(tool, requirement: #"identifier "com.example.notch-test""#))
}

@Test func rejectsCodeFromSomeoneElse() throws {
    // Ad-hoc signed, so it can't carry the release certificate.
    let tool = try signedTool(identifier: "local.mantel.app")
    let release = #"identifier "local.mantel.app" and certificate leaf = H"e860aba5c846e315bae3f058b509d31c776ba0d7""#
    #expect(!UpdateVerifier.satisfies(tool, requirement: release))
}

@Test func rejectsAMalformedRequirement() throws {
    let tool = try signedTool(identifier: "com.example.notch-test")
    #expect(!UpdateVerifier.satisfies(tool, requirement: "this is not a requirement"))
}
