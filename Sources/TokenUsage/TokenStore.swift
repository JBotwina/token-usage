import Foundation
import Security

/// Secrets live as individual files under Application Support, mode 0600.
enum SecretStore {
    private static var memory: [String: String] = [:]

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TokenUsage", isDirectory: true)
    }

    static func url(_ fileName: String) -> URL {
        supportDir.appendingPathComponent(fileName)
    }

    static func save(_ value: String, as fileName: String) throws {
        let cleaned = value.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { throw TokenStoreError.empty }

        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try cleaned.write(to: url(fileName), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url(fileName).path
        )
        memory[fileName] = cleaned
    }

    static func load(_ fileName: String) -> String? {
        if let cached = memory[fileName], !cached.isEmpty { return cached }
        let path = url(fileName)
        guard FileManager.default.fileExists(atPath: path.path),
              let raw = try? String(contentsOf: path, encoding: .utf8) else {
            return nil
        }
        let cleaned = raw.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        memory[fileName] = cleaned
        return cleaned
    }

    static func delete(_ fileName: String) {
        memory[fileName] = nil
        try? FileManager.default.removeItem(at: url(fileName))
    }
}

/// Persists the ElevenLabs API key (`sk_…`). Needs the `user_read` permission
/// on the key itself or `/v1/user/subscription` answers 401.
enum ElevenLabsKeyStore {
    private static let fileName = "elevenlabs-key"

    static func save(_ key: String) throws { try SecretStore.save(key, as: fileName) }
    static func load() -> String? { SecretStore.load(fileName) }
    static func delete() { SecretStore.delete(fileName) }
    static var hasKey: Bool { load() != nil }
}

/// Persists the long-lived Claude OAuth token (`sk-ant-oat01-…`).
///
/// Stored under Application Support with mode 0600 — not Keychain.
/// Ad-hoc re-signs on every `install-app.sh` change the code signature, so a
/// Keychain item would re-prompt for the login password (often 3× per launch
/// as the poller reads the token). A local file survives reinstalls silently.
enum TokenStore {
    private static let keychainService = "com.tokenusage.claude"
    private static let keychainAccount = "setup-token"
    private static let fileName = "token"

    static func save(_ token: String) throws {
        try SecretStore.save(token, as: fileName)
        // Drop any legacy Keychain copy so old prompts never return.
        deleteKeychainLegacy()
    }

    static func load() -> String? {
        if let fromFile = SecretStore.load(fileName) { return fromFile }

        // One-shot migration from older Keychain-backed installs.
        if let fromKeychain = loadKeychainLegacy(), !fromKeychain.isEmpty {
            try? save(fromKeychain) // also wipes Keychain
            return SecretStore.load(fileName)
        }

        return nil
    }

    static func delete() {
        SecretStore.delete(fileName)
        deleteKeychainLegacy()
    }

    static var hasToken: Bool { load() != nil }

    // MARK: - Legacy Keychain (read once, then remove)

    private static func loadKeychainLegacy() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
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

    private static func deleteKeychainLegacy() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum TokenStoreError: LocalizedError {
    case empty
    case io(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Token is empty"
        case .io(let m): return m
        }
    }
}
