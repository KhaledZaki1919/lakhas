import Foundation

/// The social platforms a recipe link can come from (PROJECT_PROMPT.md §4.4).
public enum RecipePlatform: String, Codable, Sendable, CaseIterable {
    case tiktok, instagram, youtube

    public var displayName: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        }
    }

    /// Registrable domains; their subdomains (www., m., vm., vt.) are included.
    var domains: [String] {
        switch self {
        case .tiktok: ["tiktok.com"]
        case .instagram: ["instagram.com"]
        case .youtube: ["youtube.com", "youtu.be"]
        }
    }
}

/// Recipe links: which ones are accepted, and their canonical form. The page fetcher contacts
/// only these hosts, over HTTPS (PROJECT_PROMPT.md §3.6).
public enum RecipeLink {
    public static var allowedDomains: [String] { RecipePlatform.allCases.flatMap(\.domains) }

    /// HTTPS, default port, no credentials, and an allow-listed host.
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, platform(of: url) != nil else {
            return false
        }
        return url.port == nil || url.port == 443
    }

    public static func platform(of url: URL) -> RecipePlatform? {
        guard let host = url.host?.lowercased() else { return nil }
        return RecipePlatform.allCases.first { platform in
            platform.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// A supported link typed or pasted by the user, or found in shared text ("Check this out
    /// https://vm.tiktok.com/…"). Adds https:// when missing and upgrades http://. nil when there
    /// is no TikTok, Instagram or YouTube link.
    public static func parse(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates: [String] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            candidates = detector.matches(in: trimmed, range: range).compactMap { $0.url?.absoluteString }
        }
        candidates.append(trimmed)
        for candidate in candidates {
            var text = candidate
            if text.lowercased().hasPrefix("http://") { text = "https://" + text.dropFirst("http://".count) }
            if !text.lowercased().hasPrefix("https://") { text = "https://" + text }
            if let url = URL(string: text), isAllowed(url) { return url }
        }
        return nil
    }

    /// The form the fetcher asks for. YouTube links of every shape become `watch?v=ID` (its page
    /// carries the full description); TikTok and Instagram drop tracking parameters.
    public static func canonical(_ url: URL) -> URL {
        guard let platform = platform(of: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        components.fragment = nil
        switch platform {
        case .youtube:
            guard let id = youTubeID(url) else { break }
            components.host = "www.youtube.com"
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: id)]
        case .tiktok, .instagram:
            components.query = nil
        }
        return components.url ?? url
    }

    /// The 11-character video ID of youtu.be/ID, /watch?v=ID, /shorts/ID, /live/ID and /embed/ID links.
    static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            id = parts.first
        } else if parts.first == "watch" {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
        } else if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) {
            id = parts[1]
        }
        guard let id, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        return id
    }

    /// "@name" from TikTok and YouTube paths (/@name/video/…, /@name).
    public static func handle(in url: URL) -> String? {
        url.path.split(separator: "/").first { $0.hasPrefix("@") && $0.count > 1 }.map(String.init)
    }
}
