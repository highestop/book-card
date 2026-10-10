import Foundation
import XCTest
@testable import BookCardCore

final class StorageTests: XCTestCase {
    func testCacheRoundTripAndDeletionRemainInsideApplicationDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = try DiskStore(directory: directory)
        let first = DiskStore.profile("synthetic-first")
        let second = DiskStore.profile("synthetic-second")
        let book = Book(id: "legacy", title: "Original")
        try disk.write(Cache(books: [book]), profile: first)
        try disk.write(Cache(), profile: second)
        XCTAssertEqual(try disk.read(first).books.first?.id, "legacy")
        XCTAssertTrue(try disk.read(second).books.isEmpty)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        try disk.deleteAll()
        XCTAssertTrue(try disk.read(first).books.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
