import Foundation
import Security
import CryptoKit

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
    init(directory customDirectory: URL? = nil) throws {
        directory = try customDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BookCard", isDirectory: true)
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
