import Foundation
import Security

/// One secret in the keychain and nowhere else: not in UserDefaults, which
/// any process in the sandbox can read, and never in the project, which is
/// the one thing the app exports.
struct KeychainItem {
    let service: String
    let account: String

    /// The writer's Anthropic API key.
    static let anthropicKey = KeychainItem(service: "com.siddharthnigam.take.anthropic", account: "api-key")
    /// The token a backup pushes with.
    static let backupToken = KeychainItem(service: "com.siddharthnigam.take.backup", account: "token")

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        let value = String(decoding: data, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// An empty value removes the item.
    @discardableResult
    func write(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// The Anthropic key, as the engines have always asked for it.
enum APIKeyStore {
    static func read() -> String? { KeychainItem.anthropicKey.read() }

    @discardableResult
    static func write(_ key: String) -> Bool { KeychainItem.anthropicKey.write(key) }
}
