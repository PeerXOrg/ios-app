import Foundation
import Security

public enum KeychainStore {
    public struct Credentials: Codable, Sendable, Equatable {
        public let email: String
        public let password: String
        public init(email: String, password: String) {
            self.email = email
            self.password = password
        }
    }

    public static nonisolated func saveCredentials(_ creds: Credentials) throws(KeychainError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(creds)
        } catch {
            throw .encodingFailed
        }
        try save(account: "credentials", data: data)
    }

    public static nonisolated func loadCredentials() throws(KeychainError) -> Credentials? {
        guard let data = try load(account: "credentials") else { return nil }
        do {
            return try JSONDecoder().decode(Credentials.self, from: data)
        } catch {
            throw .decodingFailed
        }
    }

    public static nonisolated func saveJWT(_ raw: String) throws(KeychainError) {
        guard let data = raw.data(using: .utf8) else { throw .encodingFailed }
        try save(account: "jwt", data: data)
    }

    public static nonisolated func loadJWTRaw() throws(KeychainError) -> String? {
        guard let data = try load(account: "jwt") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public struct CachedQR: Codable, Sendable, Equatable {
        public let hex: String
        public let expiresAt: Date
        public init(hex: String, expiresAt: Date) {
            self.hex = hex
            self.expiresAt = expiresAt
        }
    }

    public static nonisolated func saveQRToken(_ token: CachedQR) throws(KeychainError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(token)
        } catch {
            throw .encodingFailed
        }
        try save(account: "qr-token", data: data)
    }

    public static nonisolated func loadQRToken() throws(KeychainError) -> CachedQR? {
        guard let data = try load(account: "qr-token") else { return nil }
        do {
            return try JSONDecoder().decode(CachedQR.self, from: data)
        } catch {
            throw .decodingFailed
        }
    }

    public static nonisolated func clearAll() throws(KeychainError) {
        for sync in [kSecAttrSynchronizableAny, kCFBooleanTrue!, kCFBooleanFalse!] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Constants.keychainService,
                kSecAttrSynchronizable as String: sync,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                AppLog.keychain.error("clearAll delete failed status=\(status)")
            }
        }
        AppLog.keychain.info("clearAll done")
    }

    /// Saves synced (iCloud Keychain) when available, falls back to a
    /// local-only entry when iCloud Keychain is off.
    private static nonisolated func save(account: String, data: Data) throws(KeychainError) {
        let bundle = Bundle.main.bundleIdentifier ?? "?"
        do {
            try writeItem(account: account, data: data, synchronizable: true)
            AppLog.keychain.info("save \(account, privacy: .public) ok (synced) bundle=\(bundle, privacy: .public)")
            return
        } catch let e as KeychainError {
            AppLog.keychain.error("save \(account, privacy: .public) synced failed: \(String(describing: e), privacy: .public) — retrying local-only")
        }
        try writeItem(account: account, data: data, synchronizable: false)
        AppLog.keychain.info("save \(account, privacy: .public) ok (local) bundle=\(bundle, privacy: .public)")
    }

    private static nonisolated func writeItem(
        account: String,
        data: Data,
        synchronizable: Bool
    ) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw .unhandled(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw .unhandled(addStatus)
        }
    }

    private static nonisolated func load(account: String) throws(KeychainError) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            AppLog.keychain.info("load \(account, privacy: .public) not found")
            return nil
        }
        guard status == errSecSuccess else {
            AppLog.keychain.error("load \(account, privacy: .public) failed status=\(status)")
            throw .unhandled(status)
        }

        let data = item as? Data
        AppLog.keychain.info("load \(account, privacy: .public) ok (\(data?.count ?? 0) B)")
        return data
    }
}

public enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
    case decodingFailed
    case encodingFailed
}
