import Foundation
import Combine

@MainActor public final class AppStore: ObservableObject {
    @Published public private(set) var cache = Cache()
    @Published public private(set) var hasKey = false
    @Published public private(set) var busy = false
    @Published public private(set) var status = ""
    @Published public private(set) var error: String?
    private var key: String?
    private var storage: SwiftDataStore?
    private var profile: String?
    private var cacheReadable = true
    public init(preview: Cache? = nil) {
        if let preview { cache = preview; return }
        do {
            storage = try SwiftDataStore()
            key = try KeyStore.read()
            hasKey = key != nil
            profile = key.map(SwiftDataStore.profile) ?? UserDefaults.standard.string(forKey: "lastProfile")
            if let profile { cache = try storage!.read(profile) }
        } catch {
            cacheReadable = false
            self.error = "本地数据或钥匙串读取失败。请重试；现有文件未被覆盖。"
        }
    }
    public func connect(_ candidate: String) async -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !busy else { return false }
        busy = true; error = nil; status = "正在验证 Key…"
        defer { busy = false; status = "" }
        do {
            try await WeReadClient(key: candidate).validate()
            let newProfile = SwiftDataStore.profile(candidate)
            guard let storage else { throw AppError("本地存储不可用，请重新启动应用。") }
            let local = try storage.read(newProfile)
            try KeyStore.save(candidate)
            key = candidate; profile = newProfile; hasKey = true
            UserDefaults.standard.set(newProfile, forKey: "lastProfile")
            cache = local; cacheReadable = true
            return true
        } catch { self.error = displayError(error); return false }
    }
    private var didStart = false
    private var lastAttempt: Date?
    public func start() async {
        guard !didStart else { return }
        didStart = true
        await refresh()
    }
    public func refreshIfNeeded() async {
        guard didStart, Date().timeIntervalSince(lastAttempt ?? .distantPast) > 300 else { return }
        await refresh()
    }
    public func refresh(force: Bool = false) async {
        guard let key, !busy else { return }
        guard cacheReadable else {
            error = "无法读取现有缓存，已暂停同步以保留文件。请重新连接或在设置中清除损坏的本地数据。"
            return
        }
        busy = true; error = nil; lastAttempt = Date()
        status = cache.allNotes.isEmpty ? "正在收集你的读书笔记…" : "正在检查新笔记…"
        defer { busy = false; status = "" }
        do {
            let failures = try await NotebookSync.run(cache: cache, api: WeReadClient(key: key), force: force,
                progress: { self.status = $0 }, save: { try self.persist($0, update: $1) })
            if !failures.isEmpty {
                self.error = "\(failures.count) 个来源未能更新，旧数据已保留。\(failures.prefix(3).joined(separator: "；"))"
            }
        } catch { self.error = displayError(error) }
    }
    private func persist(_ next: Cache, update: SwiftDataStore.Update) throws {
        guard let storage, let profile else { throw AppError("本地存储不可用。") }
        do { try storage.write(next, profile: profile, update: update) } catch { throw AppError("保存本地数据失败，请检查磁盘空间和权限。") }
        cache = next
    }
    public func dismissError() { error = nil }
    public func removeKey() {
        do { try KeyStore.remove(); key = nil; hasKey = false }
        catch { self.error = displayError(error) }
    }
    public func deleteData() {
        do {
            guard let storage else { throw AppError("本地存储不可用。") }
            try storage.deleteAll(); cache = Cache(); cacheReadable = true; lastAttempt = nil
        }
        catch { self.error = "清除本地数据失败，请重试。" }
    }
}
