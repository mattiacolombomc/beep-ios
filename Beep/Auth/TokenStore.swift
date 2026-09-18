import Foundation
import Security

/// Keychain-backed storage for the WeBeep web-service token and its private token.
struct TokenStore: Sendable {
    let service: String

    init(service: String = "com.mattiacolombo.Beep") { self.service = service }

    private static let tokenAccount = "webeep-token"
    private static let privateAccount = "webeep-private-token"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         // macOS: the modern keychain (same semantics as iOS), not the legacy login keychain.
         kSecUseDataProtectionKeychain as String: true]
    }

    private func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, _ account: String) throws {
        let data = Data(value.utf8)
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError(status: update) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func load() -> String? { read(Self.tokenAccount) }
    func save(_ token: String) throws { try write(token, Self.tokenAccount) }
    func loadPrivateToken() -> String? { read(Self.privateAccount) }
    func savePrivateToken(_ token: String) throws { try write(token, Self.privateAccount) }

    func clear() {
        SecItemDelete(query(Self.tokenAccount) as CFDictionary)
        SecItemDelete(query(Self.privateAccount) as CFDictionary)
    }
}

struct KeychainError: Error { let status: OSStatus }
