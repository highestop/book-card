import Foundation
import XCTest
import BookCardCore

// Import the package as an app does, without granting access to its internals.
final class PublicAPITests: XCTestCase {
    func testReadingSearchAndSortKeepUnknownProgressAndExcludeOfficialAccounts() {
        let cache = Cache(books: [
            Book(id: "a", title: "Alpha", author: "AUTHOR"),
            Book(id: "b", title: "Beta", author: "Author"),
            Book(id: "c", title: "Unknown", author: "Author"),
            Book(id: "MP_WXS_1", title: "公众号")
        ], reading: [
            "a": ReadingProgress(percent: 100, synced: Date()),
            "b": ReadingProgress(percent: 5, synced: Date())
        ])
        XCTAssertEqual(cache.readingBooks(search: "author", sort: .progressAscending).map(\.id), ["b", "a", "c"])
        XCTAssertEqual(cache.readingBooks(search: "ALPHA").map(\.id), ["a"])
        XCTAssertEqual(cache.bookCount, 3)
        XCTAssertEqual(cache.finishedBooks.map(\.id), ["a"])
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
