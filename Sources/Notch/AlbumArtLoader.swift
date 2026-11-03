import AppKit

/// Loads album art over HTTPS from Spotify's image host only, with an in-memory cache.
final class AlbumArtLoader: @unchecked Sendable {
    static let shared = AlbumArtLoader()
    private static let allowedHost = "i.scdn.co"
    private static let maxBytes = 2_000_000

    static func isAllowed(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.lowercased() == allowedHost
    }

    /// Refuses redirects that leave the allowed host.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(AlbumArtLoader.isAllowed(request.url) ? request : nil)
        }
    }

    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 20
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }

    func image(for url: URL) async -> NSImage? {
        guard Self.isAllowed(url) else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maxBytes,
              let image = NSImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
