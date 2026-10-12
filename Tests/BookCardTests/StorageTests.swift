import Foundation
import SwiftData
import XCTest
@testable import BookCardCore

@MainActor final class StorageTests: XCTestCase {
    private let first = SwiftDataStore.profile("synthetic-first")
    private let second = SwiftDataStore.profile("synthetic-second")
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    private func fixture() -> Cache {
        Cache(books: [Book(id: "b", title: "Second", author: "Author", highlights: 1, thoughts: 2, recent: 3), Book(id: "a", title: "First")],
              details: ["a": BookDetail(progress: 12, seconds: 34, progressError: "Legacy", notes: [
                Note(id: "shared", kind: "想法", quote: "Quote", thought: "Thought", chapter: "Chapter", created: 123, sectionID: "section", sectionOrder: 4),
                Note(id: "other", kind: "划线", quote: "Other")
              ], synced: date), "b": BookDetail(notes: [Note(id: "shared", kind: "划线", quote: "Separate source")], synced: date),
                "unlisted": BookDetail(notes: [], synced: date)],
              synced: date, reading: ["a": ReadingProgress(percent: 100, seconds: 456, finishedAt: 789, synced: date, updatedAt: 123)],
              readingSynced: date, notesSynced: date)
    }
    private func save(_ cache: Cache, in store: SwiftDataStore, profile: String) throws {
        try store.write(cache, profile: profile, update: .library)
        for id in cache.details.keys { try store.write(cache, profile: profile, update: .detail(id)) }
        for (id, _) in cache.reading ?? [:] { try store.write(cache, profile: profile, update: .reading(id)) }
        try store.write(cache, profile: profile, update: .syncStatus)
    }
    private func assertEqual(_ actual: Cache, _ expected: Cache, file: StaticString = #filePath, line: UInt = #line) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(actual), try encoder.encode(expected), file: file, line: line)
    }
    private func legacyFile(_ directory: URL, profile: String, cache: Cache) throws -> URL {
        let url = directory.appendingPathComponent(profile + ".json")
        try JSONEncoder().encode(cache).write(to: url)
        return url
    }

    func testDatabaseRoundTripAcrossReopeningAndKeyIsolation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = fixture()
        let store = try SwiftDataStore(directory: directory)
        try save(cache, in: store, profile: first)
        try store.write(Cache(books: [Book(id: "a", title: "Another key")]), profile: second, update: .library)
        let reopened = try SwiftDataStore(directory: directory)
        try assertEqual(reopened.read(first), cache)
        XCTAssertEqual(try reopened.read(second).books.first?.title, "Another key")
        XCTAssertTrue(try reopened.read(second).details.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).contains { $0.pathExtension == "json" })
    }

    func testUpdatesOnlyChangeRequestedSourceAndDomain() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        var expected = fixture()
        try save(expected, in: store, profile: first)
        var candidate = expected
        candidate.reading?["a"]?.percent = 50
        candidate.details["b"]?.notes[0].quote = "Must not be written"
        candidate.notesSynced = date.addingTimeInterval(10)
        try store.write(candidate, profile: first, update: .reading("a"))
        expected.reading?["a"]?.percent = 50
        try assertEqual(store.read(first), expected)

        candidate = expected
        candidate.details["a"]?.notes = [Note(id: "other", kind: "想法", quote: "Edited"), Note(id: "new", kind: "划线", quote: "New")]
        candidate.reading?["a"]?.percent = 99
        try store.write(candidate, profile: first, update: .detail("a"))
        expected.details["a"] = candidate.details["a"]
        try assertEqual(store.read(first), expected)

        candidate = expected
        candidate.books.reverse(); candidate.books[0].title = "Updated title"
        candidate.details = [:]; candidate.reading = nil
        try store.write(candidate, profile: first, update: .library)
        expected.books = candidate.books
        try assertEqual(store.read(first), expected)
    }

    func testRejectedDetailUpdateRollsBackExistingChanges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        let original = fixture()
        try save(original, in: store, profile: first)
        var invalid = original
        invalid.details["a"] = BookDetail(notes: [Note(id: "other", kind: "划线", quote: "Changed"), Note(id: "other", kind: "划线", quote: "Duplicate")], synced: date.addingTimeInterval(20))
        XCTAssertThrowsError(try store.write(invalid, profile: first, update: .detail("a")))
        try assertEqual(store.read(first), original)
        try assertEqual(SwiftDataStore(directory: directory).read(first), original)
    }

    func testLegacyMigrationPreservesAllFieldsAndDeletesJSONAfterCommit() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        let original = fixture()
        let legacy = try legacyFile(directory, profile: first, cache: original)
        try assertEqual(store.read(first), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        try assertEqual(SwiftDataStore(directory: directory).read(first), original)

        let old = Data("{\"books\":[],\"details\":{}}".utf8)
        try old.write(to: directory.appendingPathComponent(second + ".json"))
        try assertEqual(store.read(second), Cache())
    }

    func testFailedMigrationKeepsOriginalFileAndCanRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        var invalid = fixture()
        let duplicate = invalid.details["a"]!.notes[0]
        invalid.details["a"]?.notes.append(duplicate)
        let legacy = try legacyFile(directory, profile: first, cache: invalid)
        let bytes = try Data(contentsOf: legacy)
        XCTAssertThrowsError(try store.read(first))
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
        _ = try legacyFile(directory, profile: first, cache: fixture())
        try assertEqual(store.read(first), fixture())
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testLeftoverLegacyFileCannotOverwriteNewerDatabase() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        let original = fixture()
        _ = try legacyFile(directory, profile: first, cache: original)
        _ = try store.read(first)
        var updated = original; updated.reading?["a"]?.percent = 75
        try store.write(updated, profile: first, update: .reading("a"))
        let leftover = try legacyFile(directory, profile: first, cache: original)
        try assertEqual(SwiftDataStore(directory: directory).read(first), updated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    func testClearRemovesAllProfilesAndRelatedNotesWithoutTouchingOtherFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        try save(fixture(), in: store, profile: first)
        try store.write(Cache(books: [Book(id: "second", title: "Second")]), profile: second, update: .library)
        let brokenProfile = SwiftDataStore.profile("unopened-legacy")
        let broken = directory.appendingPathComponent(brokenProfile + ".json")
        try Data("broken legacy data".utf8).write(to: broken)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        try store.deleteAll()
        for profile in [first, second, brokenProfile] { try assertEqual(store.read(profile), Cache()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        let schema = Schema(versionedSchema: LibrarySchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent(first + ".store"), cloudKitDatabase: .none)
        let inspection = ModelContext(try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration]))
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<LibrarySchemaV1.Annotation>()), 0)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<LibrarySchemaV1.Detail>()), 0)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<LibrarySchemaV1.Progress>()), 0)
    }

    func testInvalidProfileCannotEscapeStorageDirectory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SwiftDataStore(directory: directory)
        XCTAssertThrowsError(try store.read("../outside"))
    }
    func testV1DatabaseMigratesAndPersistsNotebookStamp() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(first + ".store")
        do {
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let source = LibrarySchemaV1.Source(id: "legacy")
            source.update(Book(id: "legacy", title: "Old book", highlights: 1, thoughts: 0, recent: 50), position: 0)
            context.insert(source)
            let detail = LibrarySchemaV1.Detail(synced: date)
            context.insert(detail); source.detail = detail
            let note = LibrarySchemaV1.Annotation(Note(id: "old", kind: "划线", quote: "Keep this original"), sourceID: "legacy", position: 0)
            context.insert(note); detail.notes = [note]
            let state = LibrarySchemaV1.SyncState(); state.legacyMigrationComplete = true
            context.insert(state); try context.save()
        }
        let store = try SwiftDataStore(directory: directory)
        var cache = try store.read(first)
        XCTAssertEqual(cache.allNotes.first?.note.quote, "Keep this original")
        XCTAssertNil(cache.details["legacy"]?.stamp)
        let stamp = NotebookStamp(cache.books[0])
        cache.details["legacy"]?.stamp = stamp
        try store.write(cache, profile: first, update: .detail("legacy"))
        let reopened = try SwiftDataStore(directory: directory)
        XCTAssertEqual(try reopened.read(first).details["legacy"]?.stamp, stamp)
        cache.details["legacy"]?.stamp = nil
        try store.write(cache, profile: first, update: .detail("legacy"))
        XCTAssertNil(try SwiftDataStore(directory: directory).read(first).details["legacy"]?.stamp)
        cache.details["legacy"]?.stamp = stamp
        try store.write(cache, profile: first, update: .detail("legacy"))
        try store.deleteAll()
        XCTAssertTrue(try store.read(first).allNotes.isEmpty)
        let schema = Schema(versionedSchema: LibrarySchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [config]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibrarySchemaV2.NotebookState>()), 0)
    }

}
