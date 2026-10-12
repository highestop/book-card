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
        body["skill_version"] = "1.0.5"
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
    func library() async throws -> [Book] {
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
        return notebooks.sorted { $0.recent == $1.recent ? $0.id < $1.id : $0.recent > $1.recent }
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
            notes.append(Note(id: "highlight:" + (try required(mark, "bookmarkId")), kind: "划线", quote: quote, thought: nil, chapter: chapters[string(mark["chapterUid"]) ?? ""] ?? "", created: noteTimestamp(mark["createTime"]), sectionID: book.official ? articleID(bookID: book.id, record: mark, thought: false) : string(mark["chapterUid"]), sectionOrder: chapterOrders[string(mark["chapterUid"]) ?? ""]))
        }
        let highlightCount = notes.count
        var cursor: Any = 0, cursors: Set<String> = ["0"], completed = false, total: Int?
        for _ in 0..<1000 {
            let page = try await call("/review/list/mine", ["bookid": book.id, "count": 100, "synckey": cursor])
            total = total ?? integer(page["totalCount"])
            for wrapper in try rows(page, "reviews") {
                guard let review = wrapper["review"] as? Object, let content = review["content"] as? String else { throw AppError("想法内容不完整。") }
                let article = review["refMpInfo"] as? Object
                notes.append(Note(id: "thought:" + (try required(review, "reviewId")), kind: "想法", quote: review["abstract"] as? String ?? "", thought: content, chapter: article?["title"] as? String ?? review["chapterName"] as? String ?? chapters[string(review["chapterUid"]) ?? ""] ?? "", created: noteTimestamp(review["createTime"]), sectionID: book.official ? articleID(bookID: book.id, record: review, thought: true) : string(review["chapterUid"]), sectionOrder: integer(review["chapterIdx"]) ?? chapterOrders[string(review["chapterUid"]) ?? ""]))
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
        return BookDetail(notes: notes.sorted { ($0.created ?? 0) > ($1.created ?? 0) }, synced: Date(), stamp: NotebookStamp(book))
    }

}
func displayError(_ error: Error) -> String {
    if error is CancellationError { return "已取消。" }
    if error is URLError { return "网络连接失败，请检查网络后重试。已缓存的数据仍可浏览。" }
    return (error as? AppError)?.message ?? "操作未完成，请重试。"
}
