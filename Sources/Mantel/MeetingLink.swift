import Foundation
import os

struct MeetingLink: Equatable {
    enum Source: String { case url, location, notes }
    let url: URL
    let source: Source
    let provider: String
}

enum MeetingLinkDetector {
    private static let log = Logger(subsystem: "local.mantel.app", category: "link")

    private static let hostRules: [(name: String, host: (String) -> Bool, path: (String) -> Bool)] = [
        ("Meet", { $0 == "meet.google.com" }, { $0.count > 1 }),
        ("Zoom", { $0 == "zoom.us" || $0.hasSuffix(".zoom.us") || $0.hasSuffix(".zoomgov.com") },
         { $0.hasPrefix("/j/") || $0.hasPrefix("/my/") || $0.hasPrefix("/wc/") || $0.hasPrefix("/s/") }),
        ("Teams", { $0 == "teams.microsoft.com" }, { $0.hasPrefix("/l/meetup-join") || $0.hasPrefix("/meet/") }),
        ("Teams", { $0 == "teams.live.com" }, { $0.hasPrefix("/meet/") }),
    ]

    /// Checks the event's URL, then location, then notes; first match wins.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let candidates: [(MeetingLink.Source, [URL])] = [
            (.url, url.map { [$0] } ?? []),
            (.location, links(in: location)),
            (.notes, links(in: notes)),
        ]
        for (source, urls) in candidates {
            for candidate in urls {
                if let provider = provider(for: candidate) {
                    log.info("meeting link found in \(source.rawValue, privacy: .public) (host: \(candidate.host ?? "?", privacy: .public))")
                    return MeetingLink(url: candidate, source: source, provider: provider)
                }
            }
        }
        return nil
    }

    private static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    private static func provider(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        return hostRules.first { $0.host(host) && $0.path(path) }?.name
    }
}
