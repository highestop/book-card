import Foundation

// Lightweight assertions allow running the contract suite with Command Line Tools alone.
class XCTestCase {}
func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never { fatalError(message, file: file, line: line) }
func XCTAssertTrue(_ value: Bool) { if !value { XCTFail("Expected true") } }
func XCTAssertFalse(_ value: Bool) { XCTAssertTrue(!value) }
func XCTAssertNil<T>(_ value: T?) { XCTAssertTrue(value == nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { if a != b { XCTFail("Values differ") } }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { if a == b { XCTFail("Values unexpectedly equal") } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { return }
    XCTFail("Expected an error")
}

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
        XCTAssertNotEqual(DiskStore.profile("test-key-a"), DiskStore.profile("test-key-b"))
        XCTAssertEqual(DiskStore.profile("test-key-a"), DiskStore.profile("test-key-a"))
        XCTAssertFalse(DiskStore.profile("test-key-a").contains("test-key"))
    }
    func testOfflineCachePreservesOriginalNotesAndProgressUnits() throws {
        let original = "第一段\n\n第二段  with spaces"
        let detail = BookDetail(progress: 1, seconds: 61, notes: [Note(id: "thought:1", kind: "想法", quote: "", thought: original, chapter: "", created: nil)], synced: Date())
        let cache = Cache(details: ["book": detail])
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(Cache.self, from: data)
        XCTAssertEqual(decoded.details["book"]?.progress, 1)
        XCTAssertEqual(decoded.details["book"]?.seconds, 61)
        XCTAssertEqual(decoded.details["book"]?.notes.first?.thought, original)
        XCTAssertNil(decoded.details["book"]?.notes.first?.created)
    }
    func testFinishedFilterAndLegacyCache() throws {
        let legacy = Data("{\"books\":[],\"details\":{}}".utf8)
        XCTAssertNil(try JSONDecoder().decode(Cache.self, from: legacy).reading)
        let books = ["done", "started", "unknown"].map { Book(id: $0, title: $0, author: "", recent: 0) }
        let cache = Cache(books: books, reading: [
            "done": ReadingProgress(percent: 100, seconds: 100, synced: Date()),
            "started": ReadingProgress(percent: 1, seconds: 10, synced: Date())
        ])
        XCTAssertEqual(cache.finishedBooks.map(\.id), ["done"])
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
            XCTAssertEqual(body["skill_version"] as? String, "1.0.4")
            XCTAssertNil(body["params"])
            return try handler(body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return WeReadClient(key: "synthetic", configuration: config)
    }
    func testLibraryPaginatesAndIncludesBooksWithoutNotes() async throws {
        let api = client { body in
            if body["api_name"] as? String == "/shelf/sync" {
                return ["books": [["bookId": "shelf", "title": "Shelf only"]]]
            }
            if body["lastSort"] == nil {
                return ["books": [["bookId": "a", "book": ["title": "A"], "sort": 20]], "hasMore": 1]
            }
            XCTAssertEqual(integer(body["lastSort"]), 20)
            return ["books": [["bookId": "b", "book": ["title": "B"], "sort": 10]], "hasMore": 0]
        }
        let books = try await api.library()
        XCTAssertEqual(Set(books.map(\.id)), Set(["a", "b", "shelf"]))
    }
    func testRepeatedCursorStopsSync() async {
        let api = client { _ in ["books": [["bookId": "a", "book": ["title": "A"], "sort": 20]], "hasMore": 1] }
        do { _ = try await api.library(); XCTFail("Must reject repeated pagination") }
        catch { XCTAssertTrue(displayError(error).contains("分页")) }
    }
    func testNotesPaginationIndependentThoughtAndOnePercentProgress() async throws {
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
            case "/book/getprogress": return ["book": ["progress": 1, "recordReadingTime": 61]]
            default: throw AppError("Unexpected operation")
            }
        }
        let book = Book(id: "a", title: "A", author: "", highlights: 1, thoughts: 2, recent: 0)
        let detail = try await api.detail(book)
        XCTAssertNil(detail.progress)
        let progress = try await api.progress(book)
        XCTAssertEqual(progress.percent, 1)
        XCTAssertEqual(progress.seconds, 61)
        XCTAssertEqual(detail.notes.count, 3)
        XCTAssertEqual(detail.notes.first(where: { $0.id == "thought:r1" })?.quote, "")
    }

    func testNotebookSyncDoesNotRequestShelfOrProgress() async throws {
        let api = client { body in
            XCTAssertEqual(body["api_name"] as? String, "/user/notebooks")
            return ["books": [], "hasMore": 0]
        }
        let books = try await api.library(includeShelf: false)
        XCTAssertEqual(books.count, 0)
    }
    func testOfficialArticleTitleSharedAcrossHighlightAndThought() async throws {
        let api = client { body in
            switch body["api_name"] as? String {
            case "/book/bookmarklist":
                return ["updated": [["bookmarkId": "MP_WXS_test_article_A_10-20", "range": "10-20", "markText": "quote"]]]
            case "/review/list/mine":
                return ["reviews": [["review": ["reviewId": "r", "content": "thought", "refMpInfo": ["reviewId": "MP_WXS_test_article_A", "title": "文章标题"]]]], "totalCount": 1, "hasMore": 0]
            default: XCTFail("Notes must not request reading progress")
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
    let cached = try await ArticleTitles.enrich(detail, previous: enriched) { _ in XCTFail("Cached title must not require network") }
    XCTAssertEqual(cached.notes.first?.chapter, "真实文章标题")
    let failed = try await ArticleTitles.enrich(detail, previous: nil) { _ in nil }
    XCTAssertEqual(failed.notes.first?.chapter, "文章（标题暂缺）")
    XCTAssertEqual(failed.notes.first?.quote, "原文")
}

func testBookSortingAndUnavailableDuration() {
    let books = ["a", "b", "c", "d"].map { Book(id: $0, title: $0, author: "", recent: 999) }
    let cache = Cache(books: books, reading: [
        "a": ReadingProgress(percent: 100, seconds: 0, synced: Date(), updatedAt: 10),
        "b": ReadingProgress(percent: 25, seconds: 42, synced: Date(), updatedAt: 20),
        "c": ReadingProgress(percent: 0, seconds: 0, synced: Date())
    ])
    XCTAssertEqual(cache.sortedBooks(by: .progressDescending).map(\.id), ["a", "b", "c", "d"])
    XCTAssertEqual(cache.sortedBooks(by: .progressAscending).map(\.id), ["c", "b", "a", "d"])
    XCTAssertEqual(cache.sortedBooks(by: .recentlyRead).map(\.id), ["b", "a", "c", "d"])
    XCTAssertEqual(cache.sortedBooks(by: .duration).first?.id, "b")
    XCTAssertEqual(cache.sortedBooks(by: .title).map(\.id), ["a", "b", "c", "d"])
    XCTAssertEqual(durationLabel(cache.reading!["a"]!), "暂无有效阅读时长")
    XCTAssertEqual(durationLabel(cache.reading!["b"]!), "阅读时长 42 秒")
}

@main struct ContractTestRunner {
    static func main() async throws {
        let unit = BookCardTests()
        try unit.testGatewayRejectsHTTPBusinessAndUpgradeErrors()
        unit.testMalformedRowsAreNotTreatedAsEmpty()
        unit.testDifferentKeysHaveIsolatedProfiles()
        try unit.testOfflineCachePreservesOriginalNotesAndProgressUnits()
        try unit.testFinishedFilterAndLegacyCache()
        unit.testArticleAndChapterIdentityGrouping()
        let sync = SyncTests()
        try await sync.testLibraryPaginatesAndIncludesBooksWithoutNotes()
        await sync.testRepeatedCursorStopsSync()
        try await sync.testNotesPaginationIndependentThoughtAndOnePercentProgress()
        await sync.testCountMismatchDoesNotProduceSnapshot()
        try await sync.testNotebookSyncDoesNotRequestShelfOrProgress()
        try await sync.testOfficialArticleTitleSharedAcrossHighlightAndThought()
        try await testArticleTitleParsingAndCacheFallback()
        testBookSortingAndUnavailableDuration()
        print("PASS: 14 contract tests")
    }
}
