import Foundation
import XCTest
@testable import BookCardCore

final class ArticleTitleTests: XCTestCase {
    func testEmptyReferenceTitleFallsThroughAndLabelsAllNotesInArticle() async throws {
        let api = SyncTests().client { body in
            switch body["api_name"] as? String {
            case "/book/bookmarklist":
                return ["updated": [["bookmarkId": "MP_WXS_test_article_1-2", "range": "1-2", "markText": "quote"]]]
            case "/review/list/mine":
                return ["reviews": [["review": ["reviewId": "thought", "content": "idea", "chapterName": "真实文章标题",
                    "refMpInfo": ["reviewId": "MP_WXS_test_article", "title": "  \n "]]]], "hasMore": 0]
            default: XCTFail("No additional metadata request is needed"); return [:]
            }
        }
        let detail = try await api.detail(Book(id: "MP_WXS_test", title: "公众号"))
        XCTAssertEqual(detail.notes.count, 2)
        XCTAssertTrue(detail.notes.allSatisfy { $0.chapter == "真实文章标题" })
    }

    func testCatalogFallbackMatchesUIDNotArrayPosition() async throws {
        let api = SyncTests().client { body in
            switch body["api_name"] as? String {
            case "/book/bookmarklist":
                return ["updated": [["bookmarkId": "h", "chapterUid": 12, "markText": "quote"]]]
            case "/review/list/mine": return ["reviews": [], "hasMore": 0]
            case "/book/chapterinfo":
                XCTAssertEqual(body["bookId"] as? String, "book")
                return ["chapters": [["chapterUid": 99, "title": "Wrong"], ["chapterUid": 12, "chapterIdx": 3, "title": "Matched"]]]
            default: throw AppError("Unexpected endpoint")
            }
        }
        let detail = try await api.detail(Book(id: "book", title: "Book"))
        XCTAssertEqual(detail.notes.first?.chapter, "Matched")
        XCTAssertEqual(detail.notes.first?.sectionOrder, 3)
    }

    func testArticleDetailUsesMPTitleAndRejectsWrongIdentityOrGenericContent() async throws {
        for scenario in 0..<3 {
            let api = SyncTests().client { body in
                XCTAssertEqual(body["api_name"] as? String, "/review/single")
                XCTAssertEqual(body["reviewId"] as? String, "MP_WXS_test_article")
                XCTAssertEqual(integer(body["commentsCount"]), 0)
                XCTAssertEqual(integer(body["likesCount"]), 0)
                var review: Object = ["reviewId": scenario == 1 ? "other" : "MP_WXS_test_article", "content": "Not an article title", "book": ["title": "Account name"]]
                if scenario != 2 { review["mpInfo"] = ["title": "文章 &amp; 标题"] }
                return ["review": review]
            }
            let title = await api.articleTitle(bookID: "MP_WXS_test", articleID: "article")
            XCTAssertEqual(title, scenario == 0 ? "文章 & 标题" : nil)
        }
    }

    func testPublicHeadingFallbackRejectsVerificationPages() {
        XCTAssertEqual(ArticleTitles.parse("<h1 class='rich_media_title' id='activity-name'> 一篇 <span>文章</span> &amp; 随想 </h1>"), "一篇 文章 & 随想")
        XCTAssertNil(ArticleTitles.parse("<meta property='og:title' content='微信公众平台'><title>环境异常</title>"))
        XCTAssertNil(ArticleTitles.parse("<title>普通页面</title>"))
    }

    @MainActor func testCachedMissingTitlesRetryAPIWithoutRedownloadingNotes() async throws {
        let book = Book(id: "MP_WXS_test", title: "公众号", highlights: 2, thoughts: 0, recent: 100)
        let synced = Date()
        let detail = BookDetail(notes: [
            Note(id: "h1", kind: "划线", quote: "First", chapter: "文章（标题暂缺）", sectionID: "article"),
            Note(id: "h2", kind: "划线", quote: "Second", chapter: "文章 article", sectionID: "article")
        ], synced: synced, stamp: NotebookStamp(book))
        let api = BookmarkTests.MemoryNotesAPI(books: [book], details: [:])
        api.titles = ["article": "来自接口的标题"]
        var cache = Cache(books: [book], details: [book.id: detail])
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0; _ = $1 })
        XCTAssertTrue(api.requests.isEmpty)
        XCTAssertEqual(api.titleRequests, ["article"])
        XCTAssertTrue(cache.allNotes.allSatisfy { $0.chapterTitle == "来自接口的标题" })
        XCTAssertEqual(cache.details[book.id]?.synced, synced)
        XCTAssertEqual(cache.details[book.id]?.stamp, NotebookStamp(book))
        api.titleRequests = []
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0; _ = $1 })
        XCTAssertTrue(api.titleRequests.isEmpty)
        XCTAssertTrue(api.requests.isEmpty)
    }

    @MainActor func testMetadataFailureKeepsNotesAndAllowsNextSyncToRetry() async throws {
        let book = Book(id: "MP_WXS_test", title: "公众号", highlights: 1, thoughts: 0, recent: 100)
        let detail = BookDetail(notes: [Note(id: "h", kind: "划线", quote: "Original", chapter: "文章（标题暂缺）", sectionID: "article")], synced: Date(), stamp: NotebookStamp(book))
        let api = BookmarkTests.MemoryNotesAPI(books: [book], details: [:])
        var cache = Cache(books: [book], details: [book.id: detail])
        _ = try await NotebookSync.run(cache: cache, api: api, enrich: { detail, old in
            try await ArticleTitles.enrich(detail, previous: old) { _ in nil }
        }, progress: { _ in }, save: { cache = $0; _ = $1 })
        XCTAssertEqual(cache.allNotes.first?.quoteText, "Original")
        XCTAssertTrue(ArticleTitles.needsEnrichment(cache.details[book.id]!))
        api.titles = ["article": "Recovered"]
        _ = try await NotebookSync.run(cache: cache, api: api, progress: { _ in }, save: { cache = $0; _ = $1 })
        XCTAssertEqual(cache.allNotes.first?.chapterTitle, "Recovered")
        XCTAssertTrue(api.requests.isEmpty)
    }
}
