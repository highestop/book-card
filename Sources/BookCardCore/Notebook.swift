import Foundation

public struct NotebookStamp: Codable, Equatable {
    let recent: Int
    let highlights: Int?
    let thoughts: Int?
    public init(_ book: Book) {
        recent = book.recent; highlights = book.highlights; thoughts = book.thoughts
    }
}

enum SyncPlan {
    // The gateway has no content delta endpoint. Reconcile unchanged books daily
    // because edits need not change the notebook's counts or latest creation time.
    static func needsDetail(_ book: Book, cached: BookDetail?, force: Bool, now: Date = Date()) -> Bool {
        guard !force, let cached, book.recent > 0, book.highlights != nil, book.thoughts != nil else { return true }
        return cached.stamp != NotebookStamp(book) || now.timeIntervalSince(cached.synced) >= 86_400
    }
}

func noteTimestamp(_ value: Any?) -> Double? {
    guard let raw = string(value), let number = Double(raw), number.isFinite, number > 0 else { return nil }
    return number > 10_000_000_000 ? number / 1_000 : number
}

public enum NoteText {
    public static func excerpt(_ text: String, limit: Int) -> String {
        let lines = text.components(separatedBy: "\n").prefix(6).joined(separator: "\n")
        let shortened = String(lines.prefix(limit))
        return shortened == text ? text : shortened.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    public static func readable(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        // Hide media markup, not the text around it. Never interpret remote HTML.
        for pattern in ["(?is)<(script|style|svg|video|audio)\\b[^>]*>.*?</\\1>", "(?is)<img\\b[^>]*>", "!\\[[^\\]]*\\]\\([^)]*\\)"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{fffc}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ["[图片]", "【图片】", "[插图]", "[image]", "[视频]", "[音频]"].contains(text.lowercased()) { return nil }
        if text.range(of: "(?i)^(https?://\\S+\\.(png|jpe?g|gif|webp|svg)(\\?\\S*)?|data:image/\\S+)$", options: .regularExpression) != nil { return nil }
        if !text.contains(where: \.isWhitespace), let url = URL(string: text),
           let host = url.host, host == "qpic.cn" || host.hasSuffix(".qpic.cn") { return nil }
        // Decode entities line by line to preserve paragraphs in quoted passages.
        text = text.components(separatedBy: "\n").map { line in
            line.contains("&") ? ArticleTitles.decodeEntities(line) : line
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

public func readingDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "zh_CN")))
}

public extension NoteEntry {
    var quoteText: String? { NoteText.readable(note.quote) }
    var thoughtText: String? { NoteText.readable(note.thought) }
    var chapterTitle: String {
        note.chapter.isEmpty ? (book.official ? "文章（标题暂缺）" : "全书笔记 · 未标注章节") : note.chapter
    }
    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let fields = [book.title, book.author, chapterTitle, quoteText ?? "", thoughtText ?? ""]
        return terms.allSatisfy { term in fields.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
    var copyText: String {
        var parts = ["《\(book.title)》", chapterTitle]
        if let quoteText { parts.append(quoteText) }
        if let thoughtText { parts.append("我的想法\n" + thoughtText) }
        if let created = note.created { parts.append(readingDate(Date(timeIntervalSince1970: created))) }
        return parts.joined(separator: "\n\n")
    }
}

public extension Cache {
    func bookmarks(sourceID: String? = nil, sectionID: String? = nil, search: String = "") -> [NoteEntry] {
        guard sectionID == nil || sourceID != nil else { return [] }
        return allNotes.filter {
            (sourceID == nil || $0.book.id == sourceID) &&
            (sectionID == nil || $0.note.groupID(official: $0.book.official) == sectionID) && $0.matches(search)
        }
    }
    func randomBookmark(excluding currentID: String?) -> NoteEntry? {
        let entries = allNotes
        return entries.filter { $0.id != currentID }.randomElement() ?? entries.first
    }
}

protocol NotesAPI {
    func library() async throws -> [Book]
    func detail(_ book: Book) async throws -> BookDetail
    func articleTitle(bookID: String, articleID: String) async -> String?
}
extension WeReadClient: NotesAPI {}

@MainActor enum NotebookSync {
    static func run(cache initial: Cache, api: NotesAPI, force: Bool = false,
                    enrich: ((BookDetail, BookDetail?) async throws -> BookDetail)? = nil,
                    progress: (String) -> Void,
                    save: (Cache, SwiftDataStore.Update) throws -> Void) async throws -> [String] {
        let books = try await api.library()
        var cache = initial
        let ids = Set(books.map(\.id))
        // Preserve offline notebooks no longer listed by the service.
        cache.books = books + initial.books.filter { !ids.contains($0.id) }
        cache.synced = Date()
        try save(cache, .library)
        let pending = books.filter { SyncPlan.needsDetail($0, cached: cache.details[$0.id], force: force) }
        func enrichTitles(_ detail: BookDetail, previous: BookDetail?, book: Book) async throws -> BookDetail {
            if let enrich { return try await enrich(detail, previous) }
            return try await ArticleTitles.enrich(detail, previous: previous) { id in
                if let title = await api.articleTitle(bookID: book.id, articleID: id), ArticleTitles.usable(title, id: id) { return title }
                guard !Task.isCancelled else { return nil }
                return await ArticleTitles.fetch(id)
            }
        }
        var failures: [String] = []
        for (index, book) in pending.enumerated() {
            try Task.checkCancellation()
            progress("同步 \(index + 1)/\(pending.count) · \(book.title)")
            let previous = cache.details[book.id]
            var detail: BookDetail
            do {
                detail = try await api.detail(book)
                // Only a complete, counted snapshot can remove previously cached notes.
                if let old = cache.details[book.id], book.highlights == nil || book.thoughts == nil,
                   !Set(old.notes.map(\.id)).isSubset(of: Set(detail.notes.map(\.id))) {
                    throw AppError("历史笔记缺失且无法核对数量，已保留缓存。")
                }
            } catch {
                if error is CancellationError { throw error }
                failures.append("《\(book.title)》：\(displayError(error))")
                continue
            }
            if book.official {
                // Publish validated content before optional public title lookups.
                // An interrupted lookup leaves no successful stamp, so it retries.
                detail.stamp = nil
                cache.details[book.id] = detail
                try save(cache, .detail(book.id))
                progress("补全文章标题 · \(book.title)")
                do { detail = try await enrichTitles(detail, previous: previous, book: book) }
                catch {
                    if error is CancellationError { throw error }
                    failures.append("《\(book.title)》：\(displayError(error))")
                    continue
                }
            }
            detail.stamp = NotebookStamp(book)
            cache.details[book.id] = detail
            // Disk failures abort immediately; a failed save must not advance a stamp.
            try save(cache, .detail(book.id))
        }
        // Retry only unresolved metadata in otherwise unchanged notebooks.
        // Keep the content's timestamp and stamp so this cannot postpone its
        // daily reconciliation or trigger a full note download on every launch.
        let pendingIDs = Set(pending.map(\.id))
        for book in books where book.official && !pendingIDs.contains(book.id) {
            guard let detail = cache.details[book.id], ArticleTitles.needsEnrichment(detail) else { continue }
            try Task.checkCancellation()
            progress("补全文章标题 · \(book.title)")
            let enriched = try await enrichTitles(detail, previous: detail, book: book)
            cache.details[book.id] = enriched
            try save(cache, .detail(book.id))
        }
        try Task.checkCancellation()
        if failures.isEmpty { cache.notesSynced = Date(); try save(cache, .syncStatus) }
        return failures
    }
}
