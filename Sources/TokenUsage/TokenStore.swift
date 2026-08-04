import Foundation
import Security

/// Stores the long-lived Claude OAuth token (`sk-ant-oat01-…`) in the Keychain.
enum TokenStore {
    private static let service = "com.tokenusage.claude"
    private static let account = "setup-token"

    static func save(_ token: String) throws {
        let cleaned = token.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { throw TokenStoreError.empty }
        let data = Data(cleaned.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError.keychain(status)
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasToken: Bool { load() != nil }
}

enum TokenStoreError: LocalizedError {
    case empty
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .empty: return "Token is empty"
        case .keychain(let s): return "Keychain error (\(s))"
        }
    }
}
