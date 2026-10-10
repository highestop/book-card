import Foundation
import Combine

@MainActor public final class AppStore: ObservableObject {
    @Published public private(set) var cache = Cache()
    @Published public private(set) var hasKey = false
    @Published public private(set) var busy = false
    @Published public private(set) var status = ""
    @Published public private(set) var error: String?
    private var key: String?
    private var disk: DiskStore?
    private var profile: String?
    public init() {
        do {
            disk = try DiskStore()
            key = try KeyStore.read()
            hasKey = key != nil
            profile = key.map(DiskStore.profile) ?? UserDefaults.standard.string(forKey: "lastProfile")
            if let profile { cache = try disk!.read(profile) }
        } catch { self.error = "本地数据或钥匙串读取失败。请重试；现有文件未被覆盖。" }
    }
    public func connect(_ candidate: String) async -> Bool {
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
            cache = local
            return true
        } catch { self.error = displayError(error); return false }
    }
    public func dismissError() { error = nil }
    public func ensureSynced(notes: Bool = false) async {
        do {
            while busy { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            if hasKey && (notes ? cache.notesSynced == nil : cache.readingSynced == nil) {
                await refresh(notes: notes)
            }
        } catch { }
    }
    public func refresh(notes: Bool = false) async {
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
    public func removeKey() {
        do { try KeyStore.remove(); key = nil; hasKey = false }
        catch { self.error = displayError(error) }
    }
    public func deleteData() {
        do { try disk?.deleteAll(); cache = Cache() }
        catch { self.error = "清除本地数据失败，请重试。" }
    }
}
