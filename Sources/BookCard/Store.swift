import Foundation
import Security
import CryptoKit
import SwiftUI

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
struct DiskStore {
    let directory: URL
    init() throws {
        directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BookCard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    static func profile(_ key: String) -> String { SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() }
    func read(_ profile: String) throws -> Cache {
        let url = directory.appendingPathComponent(profile + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Cache() }
        return try JSONDecoder().decode(Cache.self, from: Data(contentsOf: url))
    }
    func write(_ cache: Cache, profile: String) throws {
        let url = directory.appendingPathComponent(profile + ".json")
        try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func deleteAll() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }
    }
}
@MainActor final class AppStore: ObservableObject {
    @Published var cache = Cache()
    @Published var hasKey = false
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var selected: String?
    @Published var showKey = false
    private var key: String?
    private var disk: DiskStore?
    private var profile: String?
    init() {
        do {
            disk = try DiskStore()
            key = try KeyStore.read()
            hasKey = key != nil
            profile = key.map(DiskStore.profile) ?? UserDefaults.standard.string(forKey: "lastProfile")
            if let profile { cache = try disk!.read(profile) }
            selected = cache.books.first?.id
        } catch { self.error = "本地数据或钥匙串读取失败。请重试；现有文件未被覆盖。" }
    }
    func connect(_ candidate: String) async -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !busy else { return false }
        busy = true; error = nil; status = "正在验证 Key…"
        defer { busy = false; status = "" }
        do {
            try await WeReadClient(key: candidate).validate()
            let newProfile = DiskStore.profile(candidate)
            guard let disk else { throw AppError("本地存储不可用，请重新启动应用。") }
            let local = try disk.read(newProfile)
            try KeyStore.save(candidate)
            key = candidate; profile = newProfile; hasKey = true
            UserDefaults.standard.set(newProfile, forKey: "lastProfile")
            cache = local; selected = local.books.first?.id
            return true
        } catch { self.error = displayError(error); return false }
    }
    func refresh(notes: Bool = false) async {
        guard let key, !busy else { return }
        busy = true; error = nil
        status = notes ? "正在读取全部笔记本…" : "正在读取书籍列表…"
        defer { busy = false; status = "" }
        let client = WeReadClient(key: key)
        do {
            let books = try await client.library(includeShelf: !notes)
            var next = cache
            let ids = Set(books.map(\.id))
            next.books = books + cache.books.filter { !ids.contains($0.id) }
            next.synced = Date()
            try persist(next)
            let sources = notes ? books : books.filter { !$0.official }
            var failures: [String] = []
            for (index, book) in sources.enumerated() {
                try Task.checkCancellation()
                status = "\(notes ? "同步笔记" : "读取进度") \(index + 1)/\(sources.count)：\(book.title)"
                do {
                    var updated = cache
                    if notes {
                        var detail = try await client.detail(book)
                        if book.official {
                            status = "正在补全《\(book.title)》的文章标题…"
                            detail = try await ArticleTitles.enrich(detail, previous: cache.details[book.id])
                        }
                        if let old = cache.details[book.id], !Set(old.notes.map(\.id)).isSubset(of: Set(detail.notes.map(\.id))) {
                            throw AppError("部分历史笔记缺失，已保留旧缓存。")
                        }
                        updated.details[book.id] = detail
                    } else {
                        let progress = try await client.progress(book)
                        if updated.reading == nil { updated.reading = [:] }
                        updated.reading?[book.id] = progress
                    }
                    try persist(updated)
                } catch {
                    if error is CancellationError { throw error }
                    failures.append("《\(book.title)》：\(displayError(error))")
                }
            }
            if failures.isEmpty {
                var updated = cache
                if notes { updated.notesSynced = Date() } else { updated.readingSynced = Date() }
                try persist(updated)
            } else {
                self.error = "\(failures.count) 个来源未能更新，当前结果可能不完整，旧数据已保留。\(failures.prefix(3).joined(separator: "；"))"
            }
        } catch { self.error = displayError(error) }
    }
    private func persist(_ next: Cache) throws {
        guard let disk, let profile else { throw AppError("本地存储不可用。") }
        do { try disk.write(next, profile: profile) } catch { throw AppError("保存本地数据失败，请检查磁盘空间和权限。") }
        cache = next
    }
    func removeKey() {
        do { try KeyStore.remove(); key = nil; hasKey = false; showKey = false }
        catch { self.error = displayError(error) }
    }
    func deleteData() {
        do { try disk?.deleteAll(); cache = Cache(); selected = nil }
        catch { self.error = "清除本地数据失败，请重试。" }
    }
}
