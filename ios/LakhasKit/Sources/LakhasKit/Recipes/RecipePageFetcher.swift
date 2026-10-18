import Foundation

public enum RecipeFetchError: Error, Equatable, Sendable {
    /// Not HTTPS, or not a TikTok / Instagram / YouTube link.
    case unsupportedLink
    /// A redirect pointed outside the allow-list.
    case blockedRedirect
    case tooManyRedirects
    /// 404 / 410: the post was removed or the link is wrong.
    case notFound
    /// 401 / 403 / 429: a login wall or rate limit.
    case blocked
    /// Other server errors.
    case unavailable
    /// Not an HTML or JSON page (a video file, an image…).
    case notAPage
    case network
    case timedOut
    case cancelled
}

/// The public text of a recipe post: title, caption/description and creator, read from oEmbed
/// and the page's meta tags on the device. Nothing behind a login is reached.
public struct RecipePageText: Codable, Equatable, Sendable {
    public var platform: RecipePlatform
    public var url: URL
    public var title: String?
    public var caption: String?
    public var author: String?
    public var creatorHandle: String?

    public init(platform: RecipePlatform, url: URL, title: String? = nil, caption: String? = nil,
                author: String? = nil, creatorHandle: String? = nil) {
        self.platform = platform
        self.url = url
        self.title = title
        self.caption = caption
        self.author = author
        self.creatorHandle = creatorHandle
    }

    /// At most this much page text goes to the model.
    public static let maxPromptCharacters = 6000

    /// Title and caption for the prompt, without exact duplicates.
    public var text: String {
        var parts: [String] = []
        if let title { parts.append("Title: \(title)") }
        if let creator = creatorHandle ?? author { parts.append("Creator: \(creator)") }
        if let caption, caption != title { parts.append("Caption / description:\n\(caption)") }
        return String(parts.joined(separator: "\n").prefix(Self.maxPromptCharacters))
    }

    /// Whether the text can describe a recipe: enough letters once site boilerplate, links,
    /// hashtags and mentions are removed. Login walls and generic site titles fail this.
    public var isUsable: Bool {
        let fields = [title, caption].compactMap { $0 }.filter { !RecipePageParser.isBoilerplate($0) }
        let letters = fields.map(RecipePageParser.meaningful).joined(separator: " ").filter(\.isLetter).count
        return letters >= Self.minimumLetters
    }

    static let minimumLetters = 20
}

/// Fetches public recipe pages with the rules of PROJECT_PROMPT.md §3.6: allow-listed hosts
/// only, HTTPS only, per-request and overall timeouts, a body cap, no cookies, and redirects
/// followed by hand so every hop is checked against the allow-list again.
public struct RecipePageFetcher: Sendable {
    public static let maxBodyBytes = 3_000_000
    public static let maxRedirects = 5
    public static let requestTimeout: TimeInterval = 15
    public static let totalTimeout: TimeInterval = 30
    /// The phone's own browser identity: some sites send no metadata to unknown clients.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// UI tests only (`-uiTesting`): pages by canonical URL, never the network. A missing URL
    /// answers like a login wall.
    public nonisolated(unsafe) static var uiTestingPages: [String: RecipePageText]?

    private let session: URLSession
    private let language: String
    private let maxBodyBytes: Int

    public init(session: URLSession? = nil, language: String = "en", maxBodyBytes: Int = RecipePageFetcher.maxBodyBytes) {
        self.session = session ?? Self.makeSession()
        self.language = language
        self.maxBodyBytes = maxBodyBytes
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = totalTimeout
        return URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    /// The page's public text. Throws `RecipeFetchError` only when nothing could be read; an
    /// empty or login-walled page comes back with `isUsable == false`.
    public func fetch(_ link: URL) async throws -> RecipePageText {
        guard RecipeLink.isAllowed(link), let platform = RecipeLink.platform(of: link) else {
            throw RecipeFetchError.unsupportedLink
        }
        let url = RecipeLink.canonical(link)
        if let stub = Self.uiTestingPages {
            return stub[url.absoluteString] ?? RecipePageText(platform: platform, url: url, title: "Instagram")
        }
        do {
            return try await AIDeadline.run(seconds: Self.totalTimeout) {
                try await read(url, platform: platform)
            }
        } catch AIError.timedOut {
            throw RecipeFetchError.timedOut
        } catch AIError.cancelled {
            throw RecipeFetchError.cancelled
        }
    }

    private func read(_ url: URL, platform: RecipePlatform) async throws -> RecipePageText {
        var page: Page?
        var pageError: Error?
        do {
            page = try await get(url, accept: "text/html,application/xhtml+xml")
        } catch {
            pageError = error
        }
        // TikTok short links (vm./vt.) resolve to the video URL that oEmbed needs.
        let finalURL = page.map { RecipeLink.canonical($0.url) } ?? url
        var oEmbed: RecipePageParser.OEmbed?
        if let endpoint = Self.oEmbedURL(for: finalURL, platform: platform) {
            oEmbed = (try? await get(endpoint, accept: "application/json")).flatMap { RecipePageParser.oEmbed($0.body) }
        }
        if page == nil, oEmbed == nil { throw pageError ?? RecipeFetchError.unavailable }
        let meta = page.map { RecipePageParser.metadata(html: $0.text, platform: platform) } ?? RecipePageParser.Metadata()
        return RecipePageParser.combine(platform: platform, url: finalURL, meta: meta, oEmbed: oEmbed)
    }

    /// Public oEmbed endpoints (no key). Instagram's needs a Meta app token, so it has none (ADR-020).
    static func oEmbedURL(for url: URL, platform: RecipePlatform) -> URL? {
        let base: String
        switch platform {
        case .youtube: base = "https://www.youtube.com/oembed"
        case .tiktok:
            // Only a full video URL works (not a short link that failed to resolve).
            guard url.path.contains("/video/") || url.path.contains("/photo/") else { return nil }
            base = "https://www.tiktok.com/oembed"
        case .instagram: return nil
        }
        // Strictly encoded: the link's own "?", "=" and "&" must not leak into oEmbed's query.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "\(base)?url=\(encoded)&format=json")
    }

    struct Page {
        let url: URL
        let body: Data
        let truncated: Bool

        var text: String { String(decoding: body, as: UTF8.self) }
    }

    /// GET with redirects followed by hand (at most `maxRedirects`), each hop re-checked.
    func get(_ start: URL, accept: String) async throws -> Page {
        var url = start
        for _ in 0...Self.maxRedirects {
            guard RecipeLink.isAllowed(url) else {
                throw url == start ? RecipeFetchError.unsupportedLink : RecipeFetchError.blockedRedirect
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
            request.httpShouldHandleCookies = false
            request.setValue(accept, forHTTPHeaderField: "Accept")
            request.setValue(language == "ar" ? "ar,en;q=0.8" : "en,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await session.bytes(for: request, delegate: RedirectBlocker())
            } catch {
                throw Self.map(error)
            }
            guard let http = response as? HTTPURLResponse else { throw RecipeFetchError.network }
            if (300...399).contains(http.statusCode) {
                bytes.task.cancel()
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw RecipeFetchError.unavailable }
                url = next
                continue
            }
            if let failure = Self.failure(status: http.statusCode) {
                bytes.task.cancel()
                throw failure
            }
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").lowercased()
            guard ["text/", "json", "xml"].contains(where: type.contains) else {
                bytes.task.cancel()
                throw RecipeFetchError.notAPage
            }
            return try await read(bytes, from: url)
        }
        throw RecipeFetchError.tooManyRedirects
    }

    /// Reads at most `maxBodyBytes`; a longer page is cut off (metadata sits near the top).
    private func read(_ bytes: URLSession.AsyncBytes, from url: URL) async throws -> Page {
        var body = Data()
        body.reserveCapacity(256 * 1024)
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count >= maxBodyBytes {
                    bytes.task.cancel()
                    return Page(url: url, body: body, truncated: true)
                }
            }
        } catch {
            throw Self.map(error)
        }
        return Page(url: url, body: body, truncated: false)
    }

    static func failure(status: Int) -> RecipeFetchError? {
        switch status {
        case 200..<300: nil
        case 404, 410: .notFound
        case 401, 403, 429: .blocked
        default: .unavailable
        }
    }

    static func map(_ error: Error) -> RecipeFetchError {
        if let fetchError = error as? RecipeFetchError { return fetchError }
        if error is CancellationError { return .cancelled }
        switch (error as? URLError)?.code {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        default: return .network
        }
    }
}

/// Refuses automatic redirects so `RecipePageFetcher.get` can check every hop itself.
final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
