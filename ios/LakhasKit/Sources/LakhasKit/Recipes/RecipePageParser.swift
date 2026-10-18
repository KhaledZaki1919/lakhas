import Foundation

/// Reads the public text of a recipe post from HTML meta tags and oEmbed JSON. Plain pattern
/// matching, no scripts run; everything found is later sent to the model as data.
public enum RecipePageParser {
    struct Metadata: Equatable {
        var title: String?
        var ogTitle: String?
        var ogDescription: String?
        var description: String?
        /// YouTube's full description (`"shortDescription"` in the page's player data).
        var longDescription: String?
    }

    struct OEmbed: Equatable {
        var title: String?
        var authorName: String?
        var authorURL: URL?
        /// TikTok's handle without "@".
        var authorID: String?
    }

    // MARK: HTML

    static func metadata(html: String, platform: RecipePlatform) -> Metadata {
        var meta = Metadata()
        meta.title = firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html).map(clean)
        for tag in matches(#"<meta\s[^>]*>"#, in: html) {
            let attributes = self.attributes(of: tag)
            guard let content = attributes["content"].map(clean), !content.isEmpty else { continue }
            switch (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased() {
            case "og:title": meta.ogTitle = meta.ogTitle ?? content
            case "og:description": meta.ogDescription = meta.ogDescription ?? content
            case "description", "twitter:description": meta.description = meta.description ?? content
            default: break
            }
        }
        if platform == .youtube, let raw = firstMatch(#""shortDescription":"((?:[^"\\]|\\.)*)""#, in: html) {
            let decoded = (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8), options: .fragmentsAllowed)) as? String
            meta.longDescription = decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        return meta
    }

    static func oEmbed(_ data: Data) -> OEmbed? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            (json[key] as? String).map(clean).flatMap { $0.isEmpty ? nil : $0 }
        }
        let result = OEmbed(title: text("title"), authorName: text("author_name"),
                            authorURL: text("author_url").flatMap(URL.init(string:)), authorID: text("author_unique_id"))
        return result == OEmbed() ? nil : result
    }

    static func combine(platform: RecipePlatform, url: URL, meta: Metadata, oEmbed: OEmbed?) -> RecipePageText {
        var page = RecipePageText(platform: platform, url: url)
        switch platform {
        case .youtube:
            page.title = oEmbed?.title ?? meta.ogTitle ?? meta.title.map { strip($0, suffix: " - YouTube") }
            page.caption = meta.longDescription ?? meta.ogDescription ?? meta.description
            page.author = oEmbed?.authorName
            page.creatorHandle = oEmbed?.authorURL.flatMap(RecipeLink.handle(in:)) ?? RecipeLink.handle(in: url)
        case .tiktok:
            // TikTok's oEmbed "title" is the caption.
            page.caption = oEmbed?.title ?? meta.ogDescription ?? meta.description
            page.title = (meta.ogTitle ?? meta.title).map { strip($0, suffix: " | TikTok") }
            page.author = oEmbed?.authorName
            page.creatorHandle = oEmbed?.authorID.map { "@" + $0 } ?? RecipeLink.handle(in: url)
        case .instagram:
            // og:description: `12K likes, 80 comments - chef on March 3, 2025: "caption"`.
            let description = meta.ogDescription ?? meta.description
            page.caption = description.flatMap(quoted) ?? meta.ogTitle.flatMap(quoted) ?? description
            page.author = meta.ogTitle.flatMap { firstMatch(#"^(.+?) on Instagram"#, in: $0) }
            let handle = description.flatMap { firstMatch(#" - ([A-Za-z0-9._]+) on "#, in: $0) }
                ?? (meta.ogTitle ?? meta.title).flatMap { firstMatch(#"\(@([A-Za-z0-9._]+)\)"#, in: $0) }
            page.creatorHandle = handle.map { "@" + $0 }
        }
        if let title = page.title, isBoilerplate(title) { page.title = nil }
        if let caption = page.caption, isBoilerplate(caption) { page.caption = nil }
        return page
    }

    // MARK: Usability

    private static let genericTexts: Set<String> = [
        "instagram", "tiktok", "youtube", "tiktok - make your day", "make your day", "login • instagram",
        "instagram login", "log in", "sign up", "log in or sign up", "before you continue to youtube",
    ]

    private static let genericPhrases = [
        "log in to instagram", "create an account or log in", "see instagram photos and videos",
        "enjoy the videos and music you love", "share your videos with friends", "tiktok - make your day",
        "watch the latest videos", "تسجيل الدخول", "سجّل الدخول", "سجل الدخول",
    ]

    /// Site titles and login-wall text that say nothing about the post.
    static func isBoilerplate(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered.isEmpty || genericTexts.contains(lowered) { return true }
        return lowered.count < 240 && genericPhrases.contains { lowered.contains($0) }
    }

    /// Without links, hashtags and mentions.
    static func meaningful(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+|[#@]\S+"#, with: " ", options: .regularExpression)
    }

    // MARK: Helpers

    private static func strip(_ text: String, suffix: String) -> String {
        text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
    }

    /// The text between the first and the last double quote (straight or curly).
    private static func quoted(_ text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "\"" || $0 == "“" }),
              let end = text.lastIndex(where: { $0 == "\"" || $0 == "”" }), start < end else { return nil }
        let inner = text[text.index(after: start)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    /// The first capture group of the first match.
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func attributes(of tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag).map({ String(tag[$0]).lowercased() }) else { continue }
            let value = [2, 3].lazy.compactMap { Range(match.range(at: $0), in: tag) }.first.map { String(tag[$0]) }
            if result[name] == nil, let value { result[name] = value }
        }
        return result
    }

    /// Entities decoded, spaces collapsed (line breaks kept), trimmed.
    static func clean(_ text: String) -> String {
        decodeEntities(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"[ \t ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"),
              let regex = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});") else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let name = String(text[body])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[name.lowercased()]
            }
            result += replacement ?? String(text[whole])
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }
}
