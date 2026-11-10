import Foundation
import Testing
@testable import Mantel

/// Answers every request from `handler` instead of the network, and records what was asked for.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    nonisolated(unsafe) static var requested: [URL] = []
    /// When set, the request fails with this network error instead.
    nonisolated(unsafe) static var failure: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requested.append(request.url!)
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let (status, body) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubSession(_ handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
    StubProtocol.handler = handler
    StubProtocol.requested = []
    StubProtocol.failure = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: config)
}

/// One at a time: the stub's handler is shared.
@Suite(.serialized) struct UpdateDownload {
    @Test func latestVersionFromAPI() async throws {
        let session = stubSession { _ in (200, Data(#"{"tag_name":"v2.3.4"}"#.utf8)) }
        #expect(try await UpdateService.latestVersion(session: session) == AppVersion(2, 3, 4))
        #expect(StubProtocol.requested == [UpdateRules.latestReleaseURL])
    }

    @Test func latestVersionReports404Clearly() async {
        let session = stubSession { _ in (404, Data()) }
        let error = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
        #expect(error?.message == "No release found on GitHub")
    }

    @Test func latestVersionReportsRateLimit() async {
        for status in [403, 429] {
            let session = stubSession { _ in (status, Data(#"{"message":"API rate limit exceeded"}"#.utf8)) }
            let error = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
            #expect(error?.message == "GitHub is busy, will try again later")
        }
    }

    @Test func latestVersionRejectsAPageThatIsntJSON() async {
        let session = stubSession { _ in (200, Data("<html>".utf8)) }
        let error = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
        #expect(error?.message == "Couldn't read the latest release")
    }

    @Test func latestVersionReportsNetworkErrors() async {
        let session = stubSession { _ in (200, Data()) }
        StubProtocol.failure = URLError(.timedOut)
        let timedOut = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
        #expect(timedOut?.message == "Timed out talking to GitHub")
        StubProtocol.failure = URLError(.notConnectedToInternet)
        let offline = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
        #expect(offline?.message == "Couldn't reach GitHub")
    }

    @Test func latestVersionRejectsAnOddReply() async {
        let session = stubSession { _ in (200, Data(#"{"tag_name":"v2.3.4-beta"}"#.utf8)) }
        let error = await #expect(throws: UpdateService.UpdateError.self) { try await UpdateService.latestVersion(session: session) }
        #expect(error?.message == "Couldn't read the latest release")
    }

    @Test func downloadFailureLeavesAppAlone() async throws {
        let (_, dir) = try zippedApp(id: "local.mantel.app", version: "9.9.9")
        let app = try installedCopy(in: dir)
        let session = stubSession { _ in (404, Data()) }
        let error = await #expect(throws: UpdateService.UpdateError.self) {
            try await UpdateService.install(AppVersion(9, 9, 9), session: session, appURL: app,
                                            requirement: #"identifier "local.mantel.app""#, bundleID: "local.mantel.app")
        }
        #expect(error?.message == "The release has no Mantel download")
        #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("original").path))
    }

    @Test func downloadsAndInstallsTheReleaseZip() async throws {
        let (zip, dir) = try zippedApp(id: "local.mantel.app", version: "9.9.9")
        let app = try installedCopy(in: dir)
        let bytes = try Data(contentsOf: zip)
        let session = stubSession { _ in (200, bytes) }
        try await UpdateService.install(AppVersion(9, 9, 9), session: session, appURL: app,
                                        requirement: #"identifier "local.mantel.app""#, bundleID: "local.mantel.app")
        #expect(StubProtocol.requested == [UpdateRules.downloadURL(AppVersion(9, 9, 9))])
        #expect(UpdateService.infoPlist(app)?["CFBundleShortVersionString"] as? String == "9.9.9")
    }
}
