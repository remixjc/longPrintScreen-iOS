import Foundation
import Security

enum AppConfiguration {
    static let group = "group.com.remixjc.longPrintScreen"
    static let annualProduct = "com.remixjc.longPrintScreen.pro.yearly"
    static let lifetimeProduct = "com.remixjc.longPrintScreen.pro.lifetime"
    static let broadcastID = "com.remixjc.longPrintScreen.broadcast"
    static let maxPhotos = 20
}

struct ImportBatch: Codable, Identifiable {
    var id: UUID
    var created: Date
    var source: String
    var files: [String]
    var complete: Bool
    var note: String?
}

enum StorageError: LocalizedError {
    case unavailable, invalidImage, emptyBatch
    var errorDescription: String? {
        switch self {
        case .unavailable: return "共享空间不可用，请检查 App Group 签名配置。"
        case .invalidImage: return "这张图片无法读取，请选择有效的截图或照片。"
        case .emptyBatch: return "没有可导入的图片。"
        }
    }
}

enum SharedStorage {
    static func root() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.group) else {
            throw StorageError.unavailable
        }
        let inbox = url.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = inbox
        try excluded.setResourceValues(values)
        return inbox
    }

    static func create(source: String) throws -> (ImportBatch, URL) {
        let batch = ImportBatch(id: UUID(), created: Date(), source: source, files: [], complete: false)
        let directory = try root().appendingPathComponent(batch.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try save(batch, directory: directory)
        return (batch, directory)
    }

    static func save(_ batch: ImportBatch, directory: URL) throws {
        let data = try JSONEncoder().encode(batch)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func pending() throws -> [(ImportBatch, URL)] {
        let directories = try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: nil)
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                  let batch = try? JSONDecoder().decode(ImportBatch.self, from: data),
                  batch.complete, !batch.files.isEmpty else { return nil }
            return (batch, directory)
        }.sorted { $0.0.created < $1.0.created }
    }

    static func fileURLs(_ batch: ImportBatch, directory: URL) -> [URL] {
        // Manifests never get to resolve outside their own directory.
        batch.files.filter { !$0.contains("/") && !$0.contains("..") }
            .map { directory.appendingPathComponent($0) }
    }

    static func cleanExpired() {
        guard let inboxRoot = try? root(),
              let urls = try? FileManager.default.contentsOfDirectory(at: inboxRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if Date().timeIntervalSince(modified) > 7 * 86_400 { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// The extension only consumes a short-lived authorization written after StoreKit verification.
/// Keychain sharing, unlike an App Group defaults flag, is restricted by signed entitlements.
enum RecordingAuthorization {
    private static let service = "com.remixjc.longPrintScreen.recording"
    private static var query: [String: Any] {
        var value: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "verified-until"
        ]
        #if !targetEnvironment(simulator)
        if let group = Bundle.main.object(forInfoDictionaryKey: "LongShotKeychainGroup") as? String {
            value[kSecAttrAccessGroup as String] = group
        }
        #endif
        return value
    }
    @discardableResult
    static func write(validUntil: Date?) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard let validUntil else { return true }
        var entry = query
        entry[kSecValueData as String] = Data(String(validUntil.timeIntervalSince1970).utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    static var isValid: Bool {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let string = String(data: data, encoding: .utf8),
              let timestamp = Double(string) else { return false }
        return Date().timeIntervalSince1970 < timestamp
    }
}
