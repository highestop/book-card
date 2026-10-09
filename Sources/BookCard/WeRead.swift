import Foundation

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
typealias Object = [String: Any]
func string(_ value: Any?) -> String? {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
}
func integer(_ value: Any?) -> Int? {
    if let n = value as? Int { return n }
    if let s = value as? String { return Int(s) }
    return nil
}
func rows(_ object: Object, _ key: String) throws -> [Object] {
    guard let array = object[key] as? [Object] else { throw AppError("接口返回的 \(key) 数据不完整，请稍后重试。") }
    return array
}
func required(_ object: Object, _ key: String) throws -> String {
    guard let result = string(object[key]), !result.isEmpty else { throw AppError("接口缺少必要字段 \(key)。") }
    return result
}
struct Book: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var highlights: Int?
    var thoughts: Int?
    var recent: Int
    var official: Bool { id.hasPrefix("MP_WXS_") }
}
struct Note: Identifiable, Codable {
    var id: String
    var kind: String
    var quote: String
    var thought: String?
    var chapter: String
    var created: Double?
    var sectionID: String?
    var sectionOrder: Int?
}
struct NoteGroup: Identifiable {
    let id: String
    let title: String
    let notes: [Note]
}
func groupedNotes(_ notes: [Note], official: Bool) -> [NoteGroup] {
    let groups = Dictionary(grouping: notes) { note in
        note.sectionID ?? (official ? "unknown:" + note.id : "legacy:" + note.chapter)
    }
    return groups.map { id, items in
        let title = items.first(where: { !$0.chapter.isEmpty })?.chapter
            ?? (official ? "文章（标题暂缺）" : "未标注章节 / 全书想法")
        return NoteGroup(id: id, title: title, notes: items.sorted { ($0.created ?? 0) < ($1.created ?? 0) })
    }.sorted {
        if official {
            let a = $0.notes.compactMap(\.created).max() ?? 0
            let b = $1.notes.compactMap(\.created).max() ?? 0
            if a != b { return a > b }
        } else {
            let a = $0.notes.compactMap(\.sectionOrder).min() ?? Int.max
            let b = $1.notes.compactMap(\.sectionOrder).min() ?? Int.max
            if a != b { return a < b }
        }
        return $0.id < $1.id
    }
}
func articleID(bookID: String, record: Object, thought: Bool) -> String? {
    let prefix = bookID + "_"
    if thought {
        guard let ref = record["refMpInfo"] as? Object, let id = string(ref["reviewId"]), id.hasPrefix(prefix) else { return nil }
        let result = String(id.dropFirst(prefix.count))
        return result.isEmpty ? nil : result
    }
    guard let id = string(record["bookmarkId"]), let range = string(record["range"]), id.hasPrefix(prefix), id.hasSuffix("_" + range) else { return nil }
    let result = String(id.dropFirst(prefix.count).dropLast(range.count + 1))
    return result.isEmpty ? nil : result
}
struct BookDetail: Codable {
    var progress: Int?
    var seconds: Int?
    var progressError: String?
    var notes: [Note]
    var synced: Date
}
struct ReadingProgress: Codable {
    var percent: Int
    var seconds: Int?
    var finishedAt: Double?
    var synced: Date
    var updatedAt: Double?
}
enum BookSort: String, CaseIterable, Identifiable {
    case progressDescending = "阅读进度：从高到低"
    case progressAscending = "阅读进度：从低到高"
    case recentlyRead = "最近阅读"
    case duration = "阅读时长：从长到短"
    case title = "书名"
    var id: String { rawValue }
}
func durationLabel(_ progress: ReadingProgress) -> String {
    guard let seconds = progress.seconds, seconds >= 0, seconds > 0 || progress.percent == 0 else { return "暂无有效阅读时长" }
    if seconds < 60 { return "阅读时长 \(seconds) 秒" }
    return "阅读时长 \(seconds / 3600) 小时 \((seconds % 3600) / 60) 分钟"
}
struct NoteEntry: Identifiable {
    let book: Book
    let note: Note
    var id: String { "\(book.id.count):\(book.id)\(note.id)" }
}
struct Cache: Codable {
    var books: [Book] = []
    var details: [String: BookDetail] = [:]
    var synced: Date?
    var reading: [String: ReadingProgress]?
    var readingSynced: Date?
    var notesSynced: Date?
    func sortedBooks(by sort: BookSort) -> [Book] {
        books.filter { !$0.official }.sorted { a, b in
            let left = reading?[a.id], right = reading?[b.id]
            func compare(_ lhs: Double?, _ rhs: Double?, ascending: Bool = false) -> Bool? {
                if lhs == nil && rhs != nil { return false }
                if lhs != nil && rhs == nil { return true }
                if let lhs, let rhs, lhs != rhs { return ascending ? lhs < rhs : lhs > rhs }
                return nil
            }
            var order: Bool?
            switch sort {
            case .progressDescending, .progressAscending:
                order = compare(left.map { Double($0.percent) }, right.map { Double($0.percent) }, ascending: sort == .progressAscending)
            case .recentlyRead:
                order = compare(left?.updatedAt, right?.updatedAt)
            case .duration:
                order = compare(left?.seconds.flatMap { $0 > 0 ? Double($0) : nil }, right?.seconds.flatMap { $0 > 0 ? Double($0) : nil })
            case .title: break
            }
            if let order { return order }
            let names = a.title.localizedStandardCompare(b.title)
            return names == .orderedSame ? a.id < b.id : names == .orderedAscending
        }
    }
    var finishedBooks: [Book] {
        books.filter { !$0.official && reading?[$0.id]?.percent == 100 }
            .sorted { (reading?[$0.id]?.finishedAt ?? 0) > (reading?[$1.id]?.finishedAt ?? 0) }
    }
    var allNotes: [NoteEntry] {
        books.flatMap { book in (details[book.id]?.notes ?? []).map { NoteEntry(book: book, note: $0) } }
            .sorted {
                if $0.note.created == $1.note.created { return $0.id < $1.id }
                return ($0.note.created ?? 0) > ($1.note.created ?? 0)
            }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class WeReadClient {
    private let key: String
    private let session: URLSession
    init(key: String, configuration: URLSessionConfiguration? = nil) {
        self.key = key
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    static func decode(_ data: Data, status: Int) throws -> Object {
        if status == 401 { throw AppError("Key 无效或已被重置，请重新输入。") }
        if status == 403 { throw AppError("微信读书拒绝访问，请检查 Key 和账号权限。") }
        if status == 429 { throw AppError("请求过于频繁，请稍后重试。") }
        guard (200..<300).contains(status) else { throw AppError("微信读书请求失败（HTTP \(status)）。") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? Object else { throw AppError("无法识别接口响应。") }
        if let upgrade = object["upgrade_info"], !(upgrade is NSNull) { throw AppError("微信读书接口要求更新，请更新 BookCard。已缓存的数据仍可浏览。") }
        for field in ["errcode", "errCode", "code"] {
            if let code = integer(object[field]), code != 0 { throw AppError("微信读书返回错误（\(code)）。请检查 Key 或稍后重试。") }
        }
        return object
    }
    func call(_ operation: String, _ parameters: Object = [:]) async throws -> Object {
        try Task.checkCancellation()
        var body = parameters
        body["api_name"] = operation
        body["skill_version"] = "1.0.4"
        var request = URLRequest(url: URL(string: "https://i.weread.qq.com/api/agent/gateway")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        return try Self.decode(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    func validate() async throws {
        let page = try await call("/user/notebooks", ["count": 1])
        _ = try rows(page, "books")
        guard integer(page["hasMore"]) != nil else { throw AppError("Key 验证失败：接口响应不完整。") }
    }
    func library(includeShelf: Bool = true) async throws -> [Book] {
        var notebooks: [Book] = [], cursors = Set<String>(), cursor: Any?
        var completed = false
        for _ in 0..<1000 {
            var params: Object = ["count": 100]
            params["lastSort"] = cursor
            let page = try await call("/user/notebooks", params)
            let items = try rows(page, "books")
            for item in items {
                guard let info = item["book"] as? Object else { throw AppError("笔记本书籍信息不完整。") }
                notebooks.append(Book(id: try required(item, "bookId"), title: try required(info, "title"), author: string(info["author"]) ?? "", highlights: integer(item["noteCount"]), thoughts: integer(item["reviewCount"]), recent: integer(item["sort"]) ?? 0))
            }
            guard let more = integer(page["hasMore"]), [0, 1].contains(more) else { throw AppError("笔记本分页信息不完整。") }
            if more == 0 { completed = true; break }
            guard let next = items.last?["sort"], let token = string(next), cursors.insert(token).inserted else { throw AppError("笔记本分页未前进，已停止同步。") }
            cursor = next
        }
        guard completed, Set(notebooks.map(\.id)).count == notebooks.count else { throw AppError("笔记本列表不完整或有重复，保留本地数据。") }
        if !includeShelf { return notebooks }
        let shelf = try await call("/shelf/sync")
        var books = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0) })
        for item in try rows(shelf, "books") {
            let id = try required(item, "bookId")
            if var book = books[id] { book.recent = max(book.recent, integer(item["readUpdateTime"]) ?? 0); books[id] = book }
            else { books[id] = Book(id: id, title: try required(item, "title"), author: string(item["author"]) ?? "", highlights: nil, thoughts: nil, recent: integer(item["readUpdateTime"]) ?? 0) }
        }
        return books.values.sorted { $0.recent == $1.recent ? $0.title < $1.title : $0.recent > $1.recent }
    }
    func detail(_ book: Book) async throws -> BookDetail {
        let marks = try await call("/book/bookmarklist", ["bookId": book.id])
        var chapters: [String: String] = [:]
        var chapterOrders: [String: Int] = [:]
        for item in marks["chapters"] as? [Object] ?? [] {
            if let id = string(item["chapterUid"]), let title = string(item["title"]) { chapters[id] = title; chapterOrders[id] = integer(item["chapterIdx"]) }
        }
        var notes: [Note] = []
        for mark in try rows(marks, "updated") {
            guard let quote = mark["markText"] as? String else { throw AppError("划线原文缺失。") }
            notes.append(Note(id: "highlight:" + (try required(mark, "bookmarkId")), kind: "划线", quote: quote, thought: nil, chapter: chapters[string(mark["chapterUid"]) ?? ""] ?? "", created: (mark["createTime"] as? NSNumber)?.doubleValue, sectionID: book.official ? articleID(bookID: book.id, record: mark, thought: false) : string(mark["chapterUid"]), sectionOrder: chapterOrders[string(mark["chapterUid"]) ?? ""]))
        }
        let highlightCount = notes.count
        var cursor: Any = 0, cursors: Set<String> = ["0"], completed = false, total: Int?
        for _ in 0..<1000 {
            let page = try await call("/review/list/mine", ["bookid": book.id, "count": 100, "synckey": cursor])
            total = total ?? integer(page["totalCount"])
            for wrapper in try rows(page, "reviews") {
                guard let review = wrapper["review"] as? Object, let content = review["content"] as? String else { throw AppError("想法内容不完整。") }
                let article = review["refMpInfo"] as? Object
                notes.append(Note(id: "thought:" + (try required(review, "reviewId")), kind: "想法", quote: review["abstract"] as? String ?? "", thought: content, chapter: article?["title"] as? String ?? review["chapterName"] as? String ?? chapters[string(review["chapterUid"]) ?? ""] ?? "", created: (review["createTime"] as? NSNumber)?.doubleValue, sectionID: book.official ? articleID(bookID: book.id, record: review, thought: true) : string(review["chapterUid"]), sectionOrder: integer(review["chapterIdx"]) ?? chapterOrders[string(review["chapterUid"]) ?? ""]))
            }
            guard let more = integer(page["hasMore"]), [0, 1].contains(more) else { throw AppError("想法分页信息不完整。") }
            if more == 0 { completed = true; break }
            guard let next = page["synckey"], let token = string(next), cursors.insert(token).inserted else { throw AppError("想法分页未前进，已停止同步。") }
            cursor = next
        }
        guard completed, Set(notes.map(\.id)).count == notes.count,
              total == nil || total == notes.count - highlightCount,
              book.highlights == nil || book.highlights == highlightCount,
              book.thoughts == nil || book.thoughts == notes.count - highlightCount else { throw AppError("笔记数量校验未通过。请刷新书籍列表后重试，原有缓存已保留。") }
        if book.official {
            var titles: [String: String] = [:]
            for note in notes where !note.chapter.isEmpty { if let id = note.sectionID { titles[id] = note.chapter } }
            for index in notes.indices {
                if let id = notes[index].sectionID { notes[index].chapter = titles[id] ?? "文章 \(id)" }
            }
        }
        return BookDetail(notes: notes.sorted { ($0.created ?? 0) > ($1.created ?? 0) }, synced: Date())
    }
    func progress(_ book: Book) async throws -> ReadingProgress {
        let response = try await call("/book/getprogress", ["bookId": book.id])
        guard let progress = response["book"] as? Object,
              let percent = integer(progress["progress"]), (0...100).contains(percent) else {
            throw AppError("接口暂未提供有效阅读进度。")
        }
        return ReadingProgress(percent: percent, seconds: integer(progress["recordReadingTime"]),
            finishedAt: (progress["finishTime"] as? NSNumber)?.doubleValue, synced: Date(), updatedAt: (progress["updateTime"] as? NSNumber)?.doubleValue)
    }

}
func displayError(_ error: Error) -> String {
    if error is CancellationError { return "已取消。" }
    if error is URLError { return "网络连接失败，请检查网络后重试。已缓存的数据仍可浏览。" }
    return (error as? AppError)?.message ?? "操作未完成，请重试。"
}
