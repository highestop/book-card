import Foundation
import XCTest
import BookCardCore

// Import the package as an app does, without granting access to its internals.
final class PublicAPITests: XCTestCase {
    func testSourceFilterCombinesWithSearchAndPreservesNewestFirstOrder() {
        let book = Book(id: "book", title: "同名来源", author: "作者")
        let account = Book(id: "MP_WXS_account", title: "同名来源")
        let cache = Cache(books: [book, account], details: [
            book.id: BookDetail(notes: [
                Note(id: "old", kind: "划线", quote: "Reading slowly", chapter: "第一章", created: 10),
                Note(id: "new", kind: "想法", quote: "READING", thought: "Slowly", chapter: "第二章", created: 30),
                Note(id: "undated", kind: "划线", quote: "Reading slowly")
            ], synced: Date()),
            account.id: BookDetail(notes: [Note(id: "article", kind: "划线", quote: "Reading slowly", created: 20)], synced: Date())
        ])
        XCTAssertEqual(cache.bookmarks().map(\.note.id), ["new", "article", "old", "undated"])
        XCTAssertEqual(cache.bookmarks(sourceID: book.id, search: "reading SLOWLY").map(\.note.id), ["new", "old", "undated"])
        XCTAssertEqual(cache.bookmarks(sourceID: account.id).map(\.note.id), ["article"])
        XCTAssertTrue(cache.bookmarks(sourceID: account.id, search: "作者").isEmpty)
    }

    func testChapterFilterScopesIdentityAndCombinesWithSearchInTimeOrder() {
        let book = Book(id: "book", title: "同名来源")
        let account = Book(id: "MP_WXS_account", title: "同名来源")
        let cache = Cache(books: [book, account], details: [
            book.id: BookDetail(notes: [
                Note(id: "old", kind: "划线", quote: "Read slowly", chapter: "同名章节", created: 10, sectionID: "one"),
                Note(id: "new", kind: "想法", quote: "Read", thought: "Slowly", chapter: "同名章节", created: 30, sectionID: "one"),
                Note(id: "other", kind: "划线", quote: "Read slowly", chapter: "同名章节", created: 40, sectionID: "two"),
                Note(id: "undated", kind: "划线", quote: "Read slowly", chapter: "同名章节", sectionID: "one")
            ], synced: Date()),
            account.id: BookDetail(notes: [Note(id: "article", kind: "划线", quote: "Read slowly", chapter: "同名章节", created: 50, sectionID: "one")], synced: Date())
        ])
        XCTAssertEqual(cache.bookmarks(sourceID: book.id, sectionID: "one", search: "read SLOWLY").map(\.note.id), ["new", "old", "undated"])
        XCTAssertEqual(cache.bookmarks(sourceID: account.id, sectionID: "one").map(\.note.id), ["article"])
        XCTAssertEqual(cache.bookmarks(sourceID: book.id).count, 4)
        XCTAssertEqual(cache.bookmarks().count, 5)
        XCTAssertTrue(cache.bookmarks(sourceID: book.id, sectionID: "removed").isEmpty)
        XCTAssertTrue(cache.bookmarks(sectionID: "one").isEmpty)
        XCTAssertTrue(cache.bookmarks(sourceID: book.id, sectionID: "one", search: "missing").isEmpty)
    }

    func testChapterFilterUsesTheSameFallbackIdentityAsTheVisibleGroups() {
        let book = Book(id: "legacy", title: "旧书")
        let account = Book(id: "MP_WXS_legacy", title: "旧公众号")
        let notes = [
            Note(id: "a", kind: "划线", quote: "原文", chapter: "旧章节"),
            Note(id: "b", kind: "想法", quote: "", thought: "想法", chapter: "旧章节"),
            Note(id: "c", kind: "想法", quote: "", thought: "全书想法")
        ]
        let cache = Cache(books: [book, account], details: [
            book.id: BookDetail(notes: notes, synced: Date()),
            account.id: BookDetail(notes: notes, synced: Date())
        ])
        for source in [book, account] {
            let groups = cache.noteGroups(for: source)
            XCTAssertEqual(groups.count, source.official ? 3 : 2)
            for group in groups {
                XCTAssertEqual(Set(cache.bookmarks(sourceID: source.id, sectionID: group.id).map(\.note.id)), Set(group.notes.map(\.id)))
            }
        }
    }

    func testSearchRequiresEveryTermButAllowsDifferentFields() {
        let entry = NoteEntry(book: Book(id: "book", title: "山间来信", author: "Alice"), note:
            Note(id: "note", kind: "想法", quote: "<p>Read &amp; reflect</p><img src='hidden-word.png'>", thought: "慢慢生活", chapter: "第二章", created: 1791772200))
        XCTAssertTrue(entry.matches("  山间 alice\n第二章 REFLECT 慢慢  "))
        XCTAssertTrue(entry.matches("Read & reflect"))
        XCTAssertFalse(entry.matches("reflect 不存在"))
        XCTAssertFalse(entry.matches("hidden-word"))
        XCTAssertFalse(entry.matches("1791772200"))
        XCTAssertTrue(entry.matches(" \n "))
    }

    func testRandomBookmarkAvoidsCurrentAndHandlesEmptyOrSingleNote() {
        XCTAssertNil(Cache().randomBookmark(excluding: nil))
        let book = Book(id: "book", title: "Book")
        let one = Note(id: "one", kind: "划线", quote: "First", created: 10)
        var cache = Cache(books: [book], details: [book.id: BookDetail(notes: [one], synced: Date())])
        let current = cache.allNotes.first!.id
        XCTAssertEqual(cache.randomBookmark(excluding: current)?.id, current)
        cache.details[book.id]?.notes.append(Note(id: "two", kind: "划线", quote: "Second", created: 20))
        for _ in 0..<10 { XCTAssertEqual(cache.randomBookmark(excluding: current)?.note.id, "two") }
        XCTAssertTrue(Set(cache.allNotes.map(\.id)).contains(cache.randomBookmark(excluding: "removed")!.id))
    }

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
