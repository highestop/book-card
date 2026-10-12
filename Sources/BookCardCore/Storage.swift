import Foundation
import Security
import CryptoKit
import SwiftData

enum KeyStore {
    static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.BookCard.WeRead", kSecAttrAccount as String: "api-key"]
    static func read() throws -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw AppError("无法读取钥匙串，请检查系统授权后重试。") }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = base.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError("无法保存 Key 到钥匙串（\(status)）。") }
    }
    static func remove() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError("无法移除钥匙串中的 Key。") }
    }
}
@MainActor final class SwiftDataStore {
    enum Update { case library, detail(String), reading(String), syncStatus }
    let directory: URL
    private var contexts: [String: ModelContext] = [:]
    private typealias Source = LibrarySchemaV1.Source
    private typealias Detail = LibrarySchemaV1.Detail
    private typealias Annotation = LibrarySchemaV1.Annotation
    private typealias Progress = LibrarySchemaV1.Progress
    private typealias SyncState = LibrarySchemaV1.SyncState
    private typealias NotebookState = LibrarySchemaV2.NotebookState

    init(directory customDirectory: URL? = nil) throws {
        directory = try customDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BookCard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    nonisolated static func profile(_ key: String) -> String { SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() }

    func read(_ profile: String) throws -> Cache {
        let context = try context(for: profile)
        let state = try syncState(in: context)
        let sources = try context.fetch(FetchDescriptor<Source>())
        let books = sources.filter { $0.position != nil }.sorted { $0.position! < $1.position! }.map(\.value)
        var details: [String: BookDetail] = [:]
        var reading: [String: ReadingProgress] = [:]
        for source in sources {
            if let detail = source.detail { details[source.id] = detail.value }
            if let progress = source.progress { reading[source.id] = progress.value }
        }
        for stamp in try context.fetch(FetchDescriptor<NotebookState>()) { details[stamp.sourceID]?.stamp = stamp.value }
        return Cache(books: books, details: details, synced: state.synced,
                     reading: state.hasReading ? reading : nil, readingSynced: state.readingSynced, notesSynced: state.notesSynced)
    }

    func write(_ cache: Cache, profile: String, update: Update) throws {
        let context = try context(for: profile)
        try transaction(in: context) {
            let state = try syncState(in: context)
            switch update {
            case .library:
                try saveLibrary(cache.books, in: context)
                state.synced = cache.synced
            case .detail(let id):
                guard let detail = cache.details[id] else { throw AppError("没有可保存的笔记数据。") }
                try saveDetail(detail, sourceID: id, in: context)
            case .reading(let id):
                guard let progress = cache.reading?[id] else { throw AppError("没有可保存的阅读进度。") }
                try saveProgress(progress, sourceID: id, in: context)
                state.hasReading = true
            case .syncStatus:
                state.readingSynced = cache.readingSynced
                state.notesSynced = cache.notesSynced
            }
        }
        try restrictPermissions(profile)
    }

    func deleteAll() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let profiles = Set(files.filter { ["store", "json"].contains($0.pathExtension) }
            .map { $0.deletingPathExtension().lastPathComponent }.filter(Self.validProfile)).union(contexts.keys)
        for profile in profiles {
            let context = try context(for: profile, migrateLegacy: false)
            let sources = try context.fetch(FetchDescriptor<Source>())
            try transaction(in: context) {
                for source in sources { context.delete(source) }
                for stamp in try context.fetch(FetchDescriptor<NotebookState>()) { context.delete(stamp) }
                let state = try syncState(in: context)
                state.synced = nil; state.readingSynced = nil; state.notesSynced = nil
                state.hasReading = false; state.legacyMigrationComplete = true
            }
            let legacy = directory.appendingPathComponent(profile + ".json")
            if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
            try restrictPermissions(profile)
        }
    }

    private nonisolated static func validProfile(_ profile: String) -> Bool {
        profile.count == 64 && profile.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func context(for profile: String, migrateLegacy: Bool = true) throws -> ModelContext {
        guard Self.validProfile(profile) else { throw AppError("本地数据标识无效。") }
        if let context = contexts[profile] { return context }
        let schema = Schema(versionedSchema: LibrarySchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent(profile + ".store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if migrateLegacy { try migrateJSON(profile, in: context) }
        try restrictPermissions(profile)
        contexts[profile] = context
        return context
    }

    private func migrateJSON(_ profile: String, in context: ModelContext) throws {
        let legacy = directory.appendingPathComponent(profile + ".json")
        let exists = FileManager.default.fileExists(atPath: legacy.path)
        do {
            let state = try syncState(in: context)
            if !state.legacyMigrationComplete {
                let cache = exists ? try JSONDecoder().decode(Cache.self, from: Data(contentsOf: legacy)) : nil
                try transaction(in: context) {
                    if let cache {
                        try saveLibrary(cache.books, in: context)
                        for (id, detail) in cache.details { try saveDetail(detail, sourceID: id, in: context) }
                        for (id, progress) in cache.reading ?? [:] { try saveProgress(progress, sourceID: id, in: context) }
                        state.synced = cache.synced; state.readingSynced = cache.readingSynced
                        state.notesSynced = cache.notesSynced; state.hasReading = cache.reading != nil
                    }
                    state.legacyMigrationComplete = true
                }
            }
            try restrictPermissions(profile)
            // Commit the whole legacy snapshot before removing its only copy.
            // The durable marker prevents a leftover file from overwriting newer data.
            if exists { try FileManager.default.removeItem(at: legacy) }
        } catch { context.rollback(); throw error }
    }

    private func syncState(in context: ModelContext) throws -> SyncState {
        if let state = try context.fetch(FetchDescriptor<SyncState>()).first { return state }
        let state = SyncState(); context.insert(state); return state
    }

    private func source(_ id: String, in context: ModelContext) throws -> Source {
        var descriptor = FetchDescriptor<Source>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let source = try context.fetch(descriptor).first { return source }
        let source = Source(id: id); context.insert(source); return source
    }

    private func saveLibrary(_ books: [Book], in context: ModelContext) throws {
        for (position, book) in books.enumerated() { try source(book.id, in: context).update(book, position: position) }
    }

    private func saveDetail(_ value: BookDetail, sourceID: String, in context: ModelContext) throws {
        let source = try source(sourceID, in: context)
        let detail: Detail
        if let existing = source.detail { detail = existing }
        else { detail = Detail(synced: value.synced); context.insert(detail); source.detail = detail }
        detail.progress = value.progress; detail.seconds = value.seconds
        detail.progressError = value.progressError; detail.synced = value.synced
        var previous: [String: Annotation] = [:]
        for note in detail.notes { previous[note.id] = note }
        var notes: [Annotation] = []
        var ids: Set<String> = []
        for (position, note) in value.notes.enumerated() {
            guard ids.insert(note.id).inserted else { throw AppError("笔记标识重复，未保存本次更新。") }
            let record: Annotation
            if let existing = previous.removeValue(forKey: note.id) { record = existing; record.update(note, position: position) }
            else { record = Annotation(note, sourceID: sourceID, position: position); context.insert(record) }
            notes.append(record)
        }
        detail.notes = notes
        for obsolete in previous.values { context.delete(obsolete) }
        let descriptor = FetchDescriptor<NotebookState>(predicate: #Predicate { $0.sourceID == sourceID })
        let existingStamp = try context.fetch(descriptor).first
        if let stamp = value.stamp {
            if let existingStamp { existingStamp.update(stamp) }
            else { context.insert(NotebookState(sourceID: sourceID, stamp: stamp)) }
        } else if let existingStamp { context.delete(existingStamp) }
    }

    private func saveProgress(_ value: ReadingProgress, sourceID: String, in context: ModelContext) throws {
        let source = try source(sourceID, in: context)
        if let existing = source.progress { existing.update(value) }
        else { let progress = Progress(value); context.insert(progress); source.progress = progress }
    }

    private func transaction(in context: ModelContext, _ body: () throws -> Void) throws {
        do { try context.transaction(block: body) }
        catch { context.rollback(); throw error }
    }

    private func restrictPermissions(_ profile: String) throws {
        for suffix in [".store", ".store-wal", ".store-shm"] {
            let url = directory.appendingPathComponent(profile + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
    }
}
