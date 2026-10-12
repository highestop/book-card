import Foundation

public struct Book: Identifiable, Codable, Hashable {
    public init(id: String, title: String, author: String = "", highlights: Int? = nil, thoughts: Int? = nil, recent: Int = 0) {
        self.id = id; self.title = title; self.author = author
        self.highlights = highlights; self.thoughts = thoughts; self.recent = recent
    }
    public var id: String
    public var title: String
    public var author: String
    public var highlights: Int?
    public var thoughts: Int?
    public var recent: Int
    public var official: Bool { id.hasPrefix("MP_WXS_") }
}
public struct Note: Identifiable, Codable {
    public init(id: String, kind: String, quote: String, thought: String? = nil, chapter: String = "", created: Double? = nil, sectionID: String? = nil, sectionOrder: Int? = nil) {
        self.id = id; self.kind = kind; self.quote = quote; self.thought = thought
        self.chapter = chapter; self.created = created; self.sectionID = sectionID; self.sectionOrder = sectionOrder
    }
    public var id: String
    public var kind: String
    public var quote: String
    public var thought: String?
    public var chapter: String
    public var created: Double?
    public var sectionID: String?
    public var sectionOrder: Int?
    func groupID(official: Bool) -> String {
        sectionID ?? (official ? "unknown:" + id : "legacy:" + chapter)
    }
}
public struct NoteGroup: Identifiable {
    public init(id: String, title: String, notes: [Note]) { self.id = id; self.title = title; self.notes = notes }
    public let id: String
    public let title: String
    public let notes: [Note]
}
public func groupedNotes(_ notes: [Note], official: Bool) -> [NoteGroup] {
    let groups = Dictionary(grouping: notes) { note in
        note.groupID(official: official)
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
public struct BookDetail: Codable {
    public init(progress: Int? = nil, seconds: Int? = nil, progressError: String? = nil, notes: [Note], synced: Date, stamp: NotebookStamp? = nil) {
        self.progress = progress; self.seconds = seconds; self.progressError = progressError
        self.notes = notes; self.synced = synced; self.stamp = stamp
    }
    public var stamp: NotebookStamp?
    public var highlightCount: Int { notes.filter { $0.kind == "划线" }.count }
    public var thoughtCount: Int { notes.filter { $0.kind == "想法" }.count }
    public var progress: Int?
    public var seconds: Int?
    public var progressError: String?
    public var notes: [Note]
    public var synced: Date
}
// Retained only for lossless migration of existing databases and JSON archives.
public struct ReadingProgress: Codable {
    public init(percent: Int, seconds: Int? = nil, finishedAt: Double? = nil, synced: Date, updatedAt: Double? = nil) {
        self.percent = percent; self.seconds = seconds; self.finishedAt = finishedAt
        self.synced = synced; self.updatedAt = updatedAt
    }
    public var percent: Int
    public var seconds: Int?
    public var finishedAt: Double?
    public var synced: Date
    public var updatedAt: Double?
}
public struct NoteEntry: Identifiable {
    public init(book: Book, note: Note) { self.book = book; self.note = note }
    public let book: Book
    public let note: Note
    public var id: String { "\(book.id.count):\(book.id)\(note.id)" }
}
public struct Cache: Codable {
    public init(books: [Book] = [], details: [String: BookDetail] = [:], synced: Date? = nil, reading: [String: ReadingProgress]? = nil, readingSynced: Date? = nil, notesSynced: Date? = nil) {
        self.books = books; self.details = details; self.synced = synced
        self.reading = reading; self.readingSynced = readingSynced; self.notesSynced = notesSynced
    }
    public func noteSources(search: String = "") -> [Book] {
        books.filter {
            (($0.highlights ?? 0) + ($0.thoughts ?? 0) > 0 || !(details[$0.id]?.notes.isEmpty ?? true)) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }
    public func noteGroups(for book: Book, kind: String = "全部", search: String = "") -> [NoteGroup] {
        groupedNotes((details[book.id]?.notes ?? []).filter {
            (kind == "全部" || $0.kind == kind) &&
            (search.isEmpty || $0.quote.localizedCaseInsensitiveContains(search) ||
                ($0.thought ?? "").localizedCaseInsensitiveContains(search) || $0.chapter.localizedCaseInsensitiveContains(search))
        }, official: book.official)
    }
    public var books: [Book] = []
    public var details: [String: BookDetail] = [:]
    public var synced: Date?
    public var reading: [String: ReadingProgress]?
    public var readingSynced: Date?
    public var notesSynced: Date?
    public var noteBooks: [Book] {
        books.filter { (details[$0.id]?.notes.count ?? 0) > 0 || ($0.highlights ?? 0) + ($0.thoughts ?? 0) > 0 }
            .sorted {
                let a = details[$0.id]?.notes.compactMap(\.created).max() ?? Double($0.recent)
                let b = details[$1.id]?.notes.compactMap(\.created).max() ?? Double($1.recent)
                return a == b ? $0.id < $1.id : a > b
            }
    }
    public var allNotes: [NoteEntry] {
        books.flatMap { book in (details[book.id]?.notes ?? []).map { NoteEntry(book: book, note: $0) } }
            .sorted {
                let a = $0.note.created ?? 0, b = $1.note.created ?? 0
                return a == b ? $0.id < $1.id : a > b
            }
    }
}
