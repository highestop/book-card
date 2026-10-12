import Foundation

public enum ArticleTitles {
    public static func publicURL(_ id: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let encoded = id.replacingOccurrences(of: "~", with: "_").addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://mp.weixin.qq.com/s/" + encoded)
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
        }
    }
    static func decodeEntities(_ text: String) -> String {
        var result = text
        for match in matches("&#(x[0-9a-f]+|[0-9]+);", result) {
            let value = match[1]
            let number = value.lowercased().hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
            if let number, let scalar = UnicodeScalar(number) { result = result.replacingOccurrences(of: match[0], with: String(scalar)) }
        }
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func parse(_ html: String) -> String? {
        for tag in matches("<meta\\b[^>]*>", html) {
            var attributes: [String: String] = [:]
            for attribute in matches("([\\w:-]+)\\s*=\\s*([\"'])(.*?)\\2", tag[0]) { attributes[attribute[1].lowercased()] = attribute[3] }
            if (attributes["property"] ?? attributes["name"])?.lowercased() == "og:title", let content = attributes["content"] {
                if let title = title(content) { return title }
            }
        }
        // Article pages also expose their title as a heading when OG metadata
        // is absent. Do not accept a generic HTML title from a verification page.
        for heading in matches("<h[12]\\b[^>]*\\bid\\s*=\\s*([\"'])activity-name\\1[^>]*>(.*?)</h[12]>", html) {
            if let title = title(heading[2].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)) { return title }
        }
        return nil
    }
    static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = decodeEntities(raw)
        guard !value.isEmpty, !["微信公众平台", "环境异常", "安全验证", "文章（标题暂缺）"].contains(value) else { return nil }
        return value
    }
    static func fetch(_ id: String) async -> String? {
        guard let url = publicURL(id) else { return nil }
        // Public metadata uses a separate session with no bearer credentials or cookies.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 MicroMessenger/8.0.50", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 5_000_000, let html = String(data: data, encoding: .utf8) else { return nil }
        return parse(html)
    }
    static func usable(_ title: String, id: String) -> Bool {
        Self.title(title) != nil && title.trimmingCharacters(in: .whitespacesAndNewlines) != "文章 \(id)"
    }
    static func needsEnrichment(_ detail: BookDetail) -> Bool {
        detail.notes.contains { note in note.sectionID.map { !usable(note.chapter, id: $0) } ?? false }
    }
    static func enrich(_ detail: BookDetail, previous: BookDetail?, lookup: @escaping (String) async -> String? = fetch) async throws -> BookDetail {
        var result = detail
        var titles: [String: String] = [:]
        for note in previous?.notes ?? [] {
            if let id = note.sectionID, usable(note.chapter, id: id) { titles[id] = note.chapter }
        }
        for note in detail.notes {
            if let id = note.sectionID, usable(note.chapter, id: id) { titles[id] = note.chapter }
        }
        let missing = Set(detail.notes.compactMap(\.sectionID)).filter { titles[$0] == nil }.sorted()
        // Bound public metadata requests so a large article collection does not
        // pay one network timeout per title in sequence.
        try await withThrowingTaskGroup(of: (String, String?).self) { group in
            var pending = missing.makeIterator()
            func enqueue(_ id: String) {
                group.addTask {
                    try Task.checkCancellation()
                    return (id, await lookup(id))
                }
            }
            for _ in 0..<4 { if let id = pending.next() { enqueue(id) } }
            while let (id, title) = try await group.next() {
                try Task.checkCancellation()
                if let title, usable(title, id: id) { titles[id] = title }
                if let next = pending.next() { enqueue(next) }
            }
        }
        try Task.checkCancellation()
        for index in result.notes.indices {
            if let id = result.notes[index].sectionID { result.notes[index].chapter = titles[id] ?? "文章（标题暂缺）" }
        }
        return result
    }
}
