import Foundation
import Security

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

    private static var memory: String?

    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TokenUsage", isDirectory: true)
    }

    private static var tokenURL: URL {
        supportDir.appendingPathComponent(fileName)
    }

    static func save(_ token: String) throws {
        let cleaned = token.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { throw TokenStoreError.empty }

        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try cleaned.write(to: tokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        memory = cleaned

        // Drop any legacy Keychain copy so old prompts never return.
        deleteKeychainLegacy()
    }

    static func load() -> String? {
        if let memory, !memory.isEmpty { return memory }

        if let fromFile = readFile(), !fromFile.isEmpty {
            memory = fromFile
            return fromFile
        }

        // One-shot migration from older Keychain-backed installs.
        if let fromKeychain = loadKeychainLegacy(), !fromKeychain.isEmpty {
            try? save(fromKeychain) // also wipes Keychain
            return memory
        }

        return nil
    }

    static func delete() {
        memory = nil
        try? FileManager.default.removeItem(at: tokenURL)
        deleteKeychainLegacy()
    }

    static var hasToken: Bool { load() != nil }

    // MARK: - File

    private static func readFile() -> String? {
        guard FileManager.default.fileExists(atPath: tokenURL.path),
              let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else {
            return nil
        }
        let cleaned = raw.filter { !$0.isWhitespace }
        return cleaned.isEmpty ? nil : cleaned
    }

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
