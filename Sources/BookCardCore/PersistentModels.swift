import Foundation
import SwiftData

enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Source.self, Detail.self, Annotation.self, Progress.self, SyncState.self] }

    @Model final class Source {
        @Attribute(.unique) var id: String
        var title: String
        var author: String
        var highlights: Int?
        var thoughts: Int?
        var recent: Int
        // Unlisted sources preserve legacy details that have no library entry.
        var position: Int?
        @Relationship(deleteRule: .cascade, inverse: \Detail.source) var detail: Detail?
        @Relationship(deleteRule: .cascade, inverse: \Progress.source) var progress: Progress?

        init(id: String) {
            self.id = id; title = ""; author = ""; recent = 0
        }
        var value: Book { Book(id: id, title: title, author: author, highlights: highlights, thoughts: thoughts, recent: recent) }
        func update(_ book: Book, position: Int) {
            guard value != book || self.position != position else { return }
            title = book.title; author = book.author; highlights = book.highlights
            thoughts = book.thoughts; recent = book.recent; self.position = position
        }
    }

    @Model final class Detail {
        var source: Source?
        var progress: Int?
        var seconds: Int?
        var progressError: String?
        var synced: Date
        @Relationship(deleteRule: .cascade, inverse: \Annotation.detail) var notes: [Annotation] = []

        init(synced: Date) { self.synced = synced }
        var value: BookDetail {
            BookDetail(progress: progress, seconds: seconds, progressError: progressError,
                       notes: notes.sorted { $0.position < $1.position }.map(\.value), synced: synced)
        }
    }

    @Model final class Annotation {
        @Attribute(.unique) var identity: String
        var id: String
        var kind: String
        var quote: String
        var thought: String?
        var chapter: String
        var created: Double?
        var sectionID: String?
        var sectionOrder: Int?
        var position: Int
        var detail: Detail?

        init(_ note: Note, sourceID: String, position: Int) {
            identity = "\(sourceID.count):\(sourceID)\(note.id)"
            id = note.id; kind = note.kind; quote = note.quote; thought = note.thought
            chapter = note.chapter; created = note.created; sectionID = note.sectionID
            sectionOrder = note.sectionOrder; self.position = position
        }
        var value: Note {
            Note(id: id, kind: kind, quote: quote, thought: thought, chapter: chapter,
                 created: created, sectionID: sectionID, sectionOrder: sectionOrder)
        }
        func update(_ note: Note, position: Int) {
            kind = note.kind; quote = note.quote; thought = note.thought; chapter = note.chapter
            created = note.created; sectionID = note.sectionID; sectionOrder = note.sectionOrder
            self.position = position
        }
    }

    @Model final class Progress {
        var source: Source?
        var percent: Int
        var seconds: Int?
        var finishedAt: Double?
        var synced: Date
        var updatedAt: Double?

        init(_ value: ReadingProgress) {
            percent = value.percent; seconds = value.seconds; finishedAt = value.finishedAt
            synced = value.synced; updatedAt = value.updatedAt
        }
        var value: ReadingProgress {
            ReadingProgress(percent: percent, seconds: seconds, finishedAt: finishedAt, synced: synced, updatedAt: updatedAt)
        }
        func update(_ value: ReadingProgress) {
            percent = value.percent; seconds = value.seconds; finishedAt = value.finishedAt
            synced = value.synced; updatedAt = value.updatedAt
        }
    }

    @Model final class SyncState {
        @Attribute(.unique) var id: String
        var synced: Date?
        var readingSynced: Date?
        var notesSynced: Date?
        var hasReading: Bool
        var legacyMigrationComplete: Bool

        init() { id = "library"; hasReading = false; legacyMigrationComplete = false }
    }
}

// Keep V1 unchanged so existing databases can migrate without rewriting notes.
enum LibrarySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { LibrarySchemaV1.models + [NotebookState.self] }

    @Model final class NotebookState {
        @Attribute(.unique) var sourceID: String
        var recent: Int
        var highlights: Int?
        var thoughts: Int?
        init(sourceID: String, stamp: NotebookStamp) {
            self.sourceID = sourceID; recent = stamp.recent
            highlights = stamp.highlights; thoughts = stamp.thoughts
        }
        var value: NotebookStamp {
            NotebookStamp(Book(id: sourceID, title: "", highlights: highlights, thoughts: thoughts, recent: recent))
        }
        func update(_ stamp: NotebookStamp) {
            recent = stamp.recent; highlights = stamp.highlights; thoughts = stamp.thoughts
        }
    }
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)] }
}
