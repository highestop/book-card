import Foundation
import XCTest
import BookCardCore

// Import the package as an app does, without granting access to its internals.
final class PublicAPITests: XCTestCase {
    func testRecentBookmarkCardsAcrossSources() {
        let book = Book(id: "a", title: "Alpha")
        let official = Book(id: "MP_WXS_test", title: "公众号")
        let cache = Cache(books: [book, official], details: [
            book.id: BookDetail(notes: [Note(id: "a", kind: "划线", quote: "Quote", created: 10)], synced: Date()),
            official.id: BookDetail(notes: [Note(id: "b", kind: "想法", quote: "[图片]", thought: "Idea", chapter: "Article", created: 20)], synced: Date())
        ])
        XCTAssertEqual(cache.noteBooks.map(\.id), [official.id, book.id])
        XCTAssertEqual(cache.allNotes.first?.thoughtText, "Idea")
        XCTAssertNil(cache.allNotes.first?.quoteText)
        XCTAssertTrue(cache.allNotes.first!.matches("公众号 Idea"))
    }

    func testNoteSourcesIncludeOldCachedNotesWhenUpstreamCountsAreMissing() {
        let legacy = Book(id: "old", title: "Cached Source")
        let official = Book(id: "MP_WXS_1", title: "公众号", highlights: 1)
        let cache = Cache(books: [legacy, official, Book(id: "empty", title: "Empty")], details: [
            "old": BookDetail(notes: [Note(id: "h", kind: "划线", quote: "Original")], synced: Date())
        ])
        XCTAssertEqual(cache.noteSources().map(\.id), ["old", "MP_WXS_1"])
        XCTAssertEqual(cache.noteSources(search: "cached").map(\.id), ["old"])
    }

    func testNoteQueryFiltersThoughtsAndGroupsByIdentity() {
        let book = Book(id: "book", title: "Book")
        let detail = BookDetail(notes: [
            Note(id: "h", kind: "划线", quote: "Original", chapter: "Same title", sectionID: "one", sectionOrder: 2),
            Note(id: "t", kind: "想法", quote: "", thought: "My IDEA", chapter: "Same title", sectionID: "two", sectionOrder: 1)
        ], synced: Date())
        let cache = Cache(books: [book], details: [book.id: detail])
        XCTAssertEqual(cache.noteGroups(for: book).map(\.id), ["two", "one"])
        XCTAssertEqual(cache.noteGroups(for: book, kind: "想法", search: "idea").first?.notes.map(\.id), ["t"])
        XCTAssertTrue(cache.noteGroups(for: book, kind: "划线", search: "idea").isEmpty)
        XCTAssertEqual(detail.highlightCount, 1)
        XCTAssertEqual(detail.thoughtCount, 1)
    }
}
