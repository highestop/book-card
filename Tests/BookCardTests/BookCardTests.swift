import Foundation
import XCTest
@testable import BookCardCore

final class BookCardTests: XCTestCase {
    func testGatewayRejectsHTTPBusinessAndUpgradeErrors() throws {
        for (json, status) in [("{}", 401), ("{}", 403), ("{}", 429), ("{\"errcode\":-1}", 200), ("{\"errcode\":\"-2\"}", 200), ("{\"upgrade_info\":{}}", 200)] {
            XCTAssertThrowsError(try WeReadClient.decode(Data(json.utf8), status: status))
        }
        let result = try WeReadClient.decode(Data("{\"errcode\":0,\"books\":[],\"newField\":true}".utf8), status: 200)
        XCTAssertEqual(try rows(result, "books").count, 0)
    }
    func testMalformedRowsAreNotTreatedAsEmpty() {
        XCTAssertThrowsError(try rows([:], "books"))
        XCTAssertThrowsError(try rows(["books": "bad"], "books"))
        XCTAssertThrowsError(try required(["bookId": ""], "bookId"))
    }
    func testDifferentKeysHaveIsolatedProfiles() {
        XCTAssertNotEqual(SwiftDataStore.profile("test-key-a"), SwiftDataStore.profile("test-key-b"))
        XCTAssertEqual(SwiftDataStore.profile("test-key-a"), SwiftDataStore.profile("test-key-a"))
        XCTAssertFalse(SwiftDataStore.profile("test-key-a").contains("test-key"))
    }
    func testOfflineCachePreservesOriginalNotes() throws {
        let original = "第一段\n\n第二段  with spaces"
        let detail = BookDetail(notes: [Note(id: "thought:1", kind: "想法", quote: "", thought: original, chapter: "", created: nil)], synced: Date())
        let cache = Cache(details: ["book": detail])
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(Cache.self, from: data)
        XCTAssertEqual(decoded.details["book"]?.notes.first?.thought, original)
        XCTAssertNil(decoded.details["book"]?.notes.first?.created)
    }
    func testLegacyCacheMigration() throws {
        let legacy = Data(#"{"books":[],"details":{"old":{"progress":100,"seconds":61,"notes":[],"synced":0}},"reading":{"old":{"percent":100,"synced":0}}}"#.utf8)
        let cache = try JSONDecoder().decode(Cache.self, from: legacy)
        XCTAssertEqual(cache.details["old"]?.notes.count, 0)
        XCTAssertNil(cache.details["old"]?.stamp)
        XCTAssertEqual(cache.details["old"]?.progress, 100)
        XCTAssertEqual(cache.reading?["old"]?.percent, 100)
    }
    func testArticleAndChapterIdentityGrouping() {
        let bookID = "MP_WXS_test"
        XCTAssertEqual(articleID(bookID: bookID, record: ["bookmarkId": "MP_WXS_test_article_A_10-20", "range": "10-20"], thought: false), "article_A")
        XCTAssertEqual(articleID(bookID: bookID, record: ["refMpInfo": ["reviewId": "MP_WXS_test_article_A"]], thought: true), "article_A")
        XCTAssertNil(articleID(bookID: bookID, record: ["bookmarkId": "invalid", "range": "10-20"], thought: false))
        let notes = [
            Note(id: "h:1", kind: "划线", quote: "A", chapter: "相同标题", created: 1, sectionID: "A", sectionOrder: 2),
            Note(id: "t:1", kind: "想法", quote: "A", thought: "thought", chapter: "相同标题", created: 2, sectionID: "A", sectionOrder: 2),
            Note(id: "h:2", kind: "划线", quote: "B", chapter: "相同标题", created: 3, sectionID: "B", sectionOrder: 1)
        ]
        let articles = groupedNotes(notes, official: true)
        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles.first?.id, "B")
        XCTAssertEqual(articles.last?.notes.count, 2)
        XCTAssertEqual(groupedNotes(notes, official: false).first?.id, "B")
    }

}

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Object)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let object = try Self.handler!(request)
            let data = try JSONSerialization.data(withJSONObject: object)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
final class SyncTests: XCTestCase {
    func client(_ handler: @escaping (Object) throws -> Object) -> WeReadClient {
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "i.weread.qq.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096), collected = Data()
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    collected.append(buffer, count: n)
                }
                data = collected
            }
            let body = try JSONSerialization.jsonObject(with: data!) as! Object
            XCTAssertEqual(body["skill_version"] as? String, "1.0.5")
            XCTAssertNil(body["params"])
            return try handler(body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return WeReadClient(key: "synthetic", configuration: config)
    }
    func testLibraryPaginatesNotebooks() async throws {
        let api = client { body in
            XCTAssertEqual(body["api_name"] as? String, "/user/notebooks")
            if body["lastSort"] == nil {
                return ["books": [["bookId": "a", "book": ["title": "A"], "sort": 20]], "hasMore": 1]
            }
            XCTAssertEqual(integer(body["lastSort"]), 20)
            return ["books": [["bookId": "b", "book": ["title": "B"], "sort": 10]], "hasMore": 0]
        }
        let books = try await api.library()
        XCTAssertEqual(Set(books.map(\.id)), Set(["a", "b"]))
    }
    func testRepeatedCursorStopsSync() async {
        let api = client { _ in ["books": [["bookId": "a", "book": ["title": "A"], "sort": 20]], "hasMore": 1] }
        do { _ = try await api.library(); XCTFail("Must reject repeated pagination") }
        catch { XCTAssertTrue(displayError(error).contains("分页")) }
    }
    func testNotesPaginationAndIndependentThought() async throws {
        let api = client { body in
            switch body["api_name"] as? String {
            case "/book/bookmarklist": return ["updated": [["bookmarkId": "h", "markText": "original\ntext"]]]
            case "/review/list/mine":
                XCTAssertEqual(body["bookid"] as? String, "a")
                XCTAssertNil(body["bookId"])
                if integer(body["synckey"]) == 0 {
                    return ["reviews": [["review": ["reviewId": "r1", "content": "whole book thought"]]], "totalCount": 2, "hasMore": 1, "synckey": 99]
                }
                return ["reviews": [["review": ["reviewId": "r2", "content": "another thought", "abstract": "quote"]]], "totalCount": 2, "hasMore": 0]
            default: throw AppError("Unexpected operation")
            }
        }
        let book = Book(id: "a", title: "A", author: "", highlights: 1, thoughts: 2, recent: 0)
        let detail = try await api.detail(book)
        XCTAssertEqual(detail.notes.count, 3)
        XCTAssertEqual(detail.notes.first(where: { $0.id == "thought:r1" })?.quote, "")
    }

    func testNotebookSyncDoesNotRequestShelfOrProgress() async throws {
        let api = client { body in
            XCTAssertEqual(body["api_name"] as? String, "/user/notebooks")
            return ["books": [], "hasMore": 0]
        }
        let books = try await api.library()
        XCTAssertEqual(books.count, 0)
    }
    func testOfficialArticleTitleSharedAcrossHighlightAndThought() async throws {
        let api = client { body in
            switch body["api_name"] as? String {
            case "/book/bookmarklist":
                return ["updated": [["bookmarkId": "MP_WXS_test_article_A_10-20", "range": "10-20", "markText": "quote"]]]
            case "/review/list/mine":
                return ["reviews": [["review": ["reviewId": "r", "content": "thought", "refMpInfo": ["reviewId": "MP_WXS_test_article_A", "title": "文章标题"]]]], "totalCount": 1, "hasMore": 0]
            default: throw AppError("Notes must not request reading progress")
            }
        }
        let detail = try await api.detail(Book(id: "MP_WXS_test", title: "公众号", author: "", highlights: 1, thoughts: 1, recent: 0))
        let groups = groupedNotes(detail.notes, official: true)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "文章标题")
        XCTAssertEqual(groups.first?.notes.count, 2)
    }
    func testCountMismatchDoesNotProduceSnapshot() async {
        let api = client { body in
            if body["api_name"] as? String == "/book/bookmarklist" { return ["updated": []] }
            return ["reviews": [], "totalCount": 0, "hasMore": 0]
        }
        do {
            _ = try await api.detail(Book(id: "a", title: "A", author: "", highlights: 3, thoughts: 0, recent: 0))
            XCTFail("Must reject incomplete snapshot")
        } catch { XCTAssertTrue(displayError(error).contains("数量")) }
    }
}

final class BookmarkTests: XCTestCase {
func testArticleTitleParsingAndCacheFallback() async throws {
    XCTAssertEqual(ArticleTitles.parse("<meta content='标题 &amp; &#x4e2d;文 &quot;引用&quot;' property='og:title'>"), "标题 & 中文 \"引用\"")
    XCTAssertNil(ArticleTitles.parse("<html><title>环境异常</title></html>"))
    XCTAssertEqual(ArticleTitles.publicURL("abc~def")?.absoluteString, "https://mp.weixin.qq.com/s/abc_def")
    let note = Note(id: "h", kind: "划线", quote: "原文", chapter: "文章 abc", created: nil, sectionID: "abc")
    let detail = BookDetail(notes: [note], synced: Date())
    var calls = 0
    let enriched = try await ArticleTitles.enrich(detail, previous: nil) { id in
        calls += 1; XCTAssertEqual(id, "abc"); return "真实文章标题"
    }
    XCTAssertEqual(enriched.notes.first?.chapter, "真实文章标题")
    XCTAssertEqual(calls, 1)
    let cached = try await ArticleTitles.enrich(detail, previous: enriched) { _ in XCTFail("Cached title must not require network"); return nil }
    XCTAssertEqual(cached.notes.first?.chapter, "真实文章标题")
    let failed = try await ArticleTitles.enrich(detail, previous: nil) { _ in nil }
    XCTAssertEqual(failed.notes.first?.chapter, "文章（标题暂缺）")
    XCTAssertEqual(failed.notes.first?.quote, "原文")
}

func testCardProjectionAndMedia() throws {
    let book = Book(id: "b", title: "山间来信", author: "作者", recent: 30)
    let old = Note(id: "same", kind: "划线", quote: "<p>一段原文</p><img src='https://example.com/a.png'><p>第二段</p>", chapter: "第一章", created: 10)
    let latest = Note(id: "new", kind: "想法", quote: "[图片]", thought: "记得慢下来", chapter: "第二章", created: 20)
    let entry = NoteEntry(book: book, note: latest)
    XCTAssertNil(entry.quoteText)
    XCTAssertEqual(entry.thoughtText, "记得慢下来")
    XCTAssertTrue(entry.matches("山间 慢下来"))
    XCTAssertFalse(entry.matches("其他"))
    XCTAssertTrue(entry.copyText.contains("第二章"))
    XCTAssertTrue(entry.copyText.contains("我的想法"))
    XCTAssertEqual(NoteText.readable(old.quote), "一段原文\n第二段")
    XCTAssertNil(NoteText.readable("![图](https://example.com/a.png)"))
    XCTAssertNil(NoteText.readable("https://example.com/a.jpg?width=300"))
    XCTAssertNil(NoteText.readable("<img src='a'><video>x</video>"))
    XCTAssertEqual(NoteText.readable("第一段\n\n第二段  with spaces"), "第一段\n\n第二段  with spaces")
    XCTAssertEqual(NoteText.excerpt("短句", limit: 220), "短句")
    XCTAssertEqual(NoteText.excerpt("完整文字", limit: 2), "完整…")
    XCTAssertNil(NoteText.readable("https://mmbiz.qpic.cn/mmbiz_png/abc/0?wx_fmt=png"))
    XCTAssertEqual(noteTimestamp("1700000000000"), 1700000000)
    XCTAssertNil(noteTimestamp(0)); XCTAssertNil(noteTimestamp("nan"))
    let other = Book(id: "c", title: "公众号", author: "", recent: 0)
    let cache = Cache(books: [book, other], details: [
        "b": BookDetail(notes: [old, latest], synced: Date()),
        "c": BookDetail(notes: [Note(id: "same", kind: "划线", quote: "", chapter: "")], synced: Date())
    ])
    XCTAssertEqual(cache.allNotes.first?.note.id, "new")
    XCTAssertEqual(Set(cache.allNotes.map(\.id)).count, 3)
    XCTAssertEqual(cache.noteBooks.map(\.id), ["b", "c"])
    let decoded = try JSONDecoder().decode(Cache.self, from: JSONEncoder().encode(cache))
    XCTAssertEqual(decoded.allNotes.map(\.id), cache.allNotes.map(\.id))
}

func testIncrementalSyncPlan() {
    let now = Date()
    let book = Book(id: "a", title: "A", author: "", highlights: 1, thoughts: 0, recent: 100)
    var cached = BookDetail(notes: [], synced: now, stamp: NotebookStamp(book))
    XCTAssertFalse(SyncPlan.needsDetail(book, cached: cached, force: false, now: now))
    XCTAssertTrue(SyncPlan.needsDetail(book, cached: cached, force: true, now: now))
    XCTAssertTrue(SyncPlan.needsDetail(book, cached: nil, force: false, now: now))
    XCTAssertTrue(SyncPlan.needsDetail(book, cached: cached, force: false, now: now.addingTimeInterval(86_401)))
    var changed = book; changed.recent += 1
    XCTAssertTrue(SyncPlan.needsDetail(changed, cached: cached, force: false, now: now))
    changed = book; changed.highlights = 2
    XCTAssertTrue(SyncPlan.needsDetail(changed, cached: cached, force: false, now: now))
    changed = book; changed.thoughts = nil
    XCTAssertTrue(SyncPlan.needsDetail(changed, cached: cached, force: false, now: now))
    cached.stamp = nil
    XCTAssertTrue(SyncPlan.needsDetail(book, cached: cached, force: false, now: now))
}

final class MemoryNotesAPI: NotesAPI {
    var books: [Book]
    var details: [String: BookDetail]
    var failing: Set<String> = []
    var requests: [String] = []
    var cancelled = false
    var failLibrary = false
    init(books: [Book], details: [String: BookDetail]) { self.books = books; self.details = details }
    var titles: [String: String] = [:]
    var titleRequests: [String] = []
    func articleTitle(bookID: String, articleID: String) async -> String? {
        titleRequests.append(articleID)
        return titles[articleID]
    }
    func library() async throws -> [Book] {
        if failLibrary { throw URLError(.notConnectedToInternet) }
        return books
    }
    func detail(_ book: Book) async throws -> BookDetail {
        requests.append(book.id)
        if cancelled { throw CancellationError() }
        if failing.contains(book.id) { throw URLError(.timedOut) }
        guard let detail = details[book.id] else { throw AppError("Missing test fixture") }
        return detail
    }
}

@MainActor func testIncrementalSyncAndRetry() async throws {
    let books = ["a", "b"].map { Book(id: $0, title: $0, author: "", highlights: 1, thoughts: 0, recent: 100) }
    let details = Dictionary(uniqueKeysWithValues: books.map { book in
        (book.id, BookDetail(notes: [Note(id: "h", kind: "划线", quote: "original", chapter: "", created: 100)], synced: Date(), stamp: NotebookStamp(book)))
    })
    let api = MemoryNotesAPI(books: books, details: details)
    var cache = Cache(), saves = 0
    let first = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0; saves += 1 ; _ = $1 })
    XCTAssertTrue(first.isEmpty); XCTAssertEqual(api.requests, ["a", "b"]); XCTAssertEqual(saves, 4)
    XCTAssertTrue(cache.notesSynced != nil)
    api.requests = []
    _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertTrue(api.requests.isEmpty)
    api.books[1].recent = 200
    api.failing = ["b"]
    let synced = cache.notesSynced
    let failures = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(failures.count, 1); XCTAssertEqual(cache.notesSynced, synced)
    XCTAssertEqual(cache.details["b"]?.stamp?.recent, 100)
    XCTAssertEqual(cache.books.first(where: { $0.id == "b" })?.recent, 200)
    api.requests = []; api.failing = []
    _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(api.requests, ["b"])
    XCTAssertEqual(cache.details["b"]?.stamp?.recent, 200)
    api.requests = []
    _ = try await NotebookSync.run(cache: cache, api: api, force: true, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(api.requests, ["a", "b"])
}

@MainActor func testDeletionReconciliationAndOfflineSources() async throws {
    let book = Book(id: "a", title: "A", author: "", highlights: 1, thoughts: 0, recent: 100)
    let old = BookDetail(notes: [Note(id: "old", kind: "划线", quote: "old", chapter: "")], synced: Date(), stamp: NotebookStamp(book))
    var deleted = book; deleted.highlights = 0
    let api = MemoryNotesAPI(books: [deleted], details: ["a": BookDetail(notes: [], synced: Date())])
    var cache = Cache(books: [book], details: ["a": old])
    _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertTrue(cache.allNotes.isEmpty)
    XCTAssertTrue(cache.noteBooks.isEmpty)
    cache = Cache(books: [book], details: ["a": old])
    api.books[0].highlights = nil
    let failures = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(failures.count, 1); XCTAssertEqual(cache.allNotes.count, 1)
    api.books = []
    _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(cache.allNotes.count, 1)
    XCTAssertEqual(cache.books.first?.id, "a")
}

@MainActor func testSyncCancellationAndDiskFailure() async throws {
    let book = Book(id: "a", title: "A", author: "", highlights: 0, thoughts: 0, recent: 1)
    let api = MemoryNotesAPI(books: [book], details: ["a": BookDetail(notes: [], synced: Date())])
    var cache = Cache()
    api.cancelled = true
    do {
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0 ; _ = $1 })
        XCTFail("Cancellation must escape")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertNil(cache.notesSynced); XCTAssertNil(cache.details["a"])
    api.cancelled = false
    var saves = 0
    do {
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { next, _ in
            saves += 1
            if saves == 2 { throw AppError("Disk full") }
            cache = next
        })
        XCTFail("A failed disk write must abort")
    } catch { XCTAssertEqual(displayError(error), "Disk full") }
    XCTAssertNil(cache.details["a"])
    api.failLibrary = true; saves = 0
    do {
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { _, _ in saves += 1 })
        XCTFail("Offline must retain cache")
    } catch { XCTAssertEqual(saves, 0) }
}

func testAPIRejectsMalformedAndRepeatedReviews() async throws {
    let suite = SyncTests()
    let book = Book(id: "a", title: "A", author: "", recent: 0)
    for scenario in 0..<3 {
        let api = suite.client { body in
            if body["api_name"] as? String == "/book/bookmarklist" {
                if scenario == 0 { return ["updated": [["bookmarkId": "h"]]] }
                return ["updated": []]
            }
            if scenario == 1 { return ["reviews": [], "hasMore": 1, "synckey": 0] }
            return ["reviews": [["review": ["reviewId": "same", "content": "a"]], ["review": ["reviewId": "same", "content": "b"]]], "hasMore": 0]
        }
        do { _ = try await api.detail(book); XCTFail("Must reject incomplete or repeated records") }
        catch { XCTAssertTrue(error is AppError) }
    }
}

@MainActor func testArticleContentAppearsBeforeMetadataAndRetries() async throws {
    let book = Book(id: "MP_WXS_test", title: "公众号", author: "", highlights: 1, thoughts: 0, recent: 10)
    let raw = BookDetail(notes: [Note(id: "h", kind: "划线", quote: "原文", chapter: "", created: 10, sectionID: "article")], synced: Date())
    let api = MemoryNotesAPI(books: [book], details: [book.id: raw])
    var cache = Cache()
    do {
        _ = try await NotebookSync.run(cache: cache, api: api, enrich: { _, _ in
            XCTAssertEqual(cache.allNotes.count, 1)
            XCTAssertNil(cache.details[book.id]?.stamp)
            throw CancellationError()
        }, progress: { _ in }, save: { cache = $0 ; _ = $1 })
        XCTFail("Interrupted metadata must retry")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertTrue(SyncPlan.needsDetail(book, cached: cache.details[book.id], force: false))
    _ = try await NotebookSync.run(cache: cache, api: api, enrich: { detail, _ in
        var enriched = detail; enriched.notes[0].chapter = "真实标题"; return enriched
    }, progress: { _ in }, save: { cache = $0 ; _ = $1 })
    XCTAssertEqual(cache.allNotes.first?.chapterTitle, "真实标题")
    XCTAssertEqual(cache.details[book.id]?.stamp, NotebookStamp(book))
}

actor LookupCounter {
    var running = 0, peak = 0, total = 0
    func start() { running += 1; total += 1; peak = max(peak, running) }
    func end() { running -= 1 }
    func result() -> (Int, Int) { (peak, total) }
}
func testArticleMetadataConcurrencyIsBounded() async throws {
    let counter = LookupCounter()
    let notes = (0..<11).map { Note(id: "h:\($0)", kind: "划线", quote: "原文", chapter: "", sectionID: "article\($0)") }
    let enriched = try await ArticleTitles.enrich(BookDetail(notes: notes, synced: Date()), previous: nil) { id in
        await counter.start()
        try? await Task.sleep(for: .milliseconds(10))
        await counter.end()
        return "标题 " + id
    }
    let (peak, total) = await counter.result()
    XCTAssertTrue(peak <= 4); XCTAssertTrue(peak > 1); XCTAssertEqual(total, 11)
    XCTAssertTrue(enriched.notes.allSatisfy { $0.chapter.hasPrefix("标题 article") })
}

}
