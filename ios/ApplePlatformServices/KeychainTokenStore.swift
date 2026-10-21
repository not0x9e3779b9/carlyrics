import Foundation
import Security
import SpotifyIntegration

actor KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "spotify-session"

    init(service: String = (Bundle.main.bundleIdentifier ?? "CarLyrics") + ".authentication") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() async throws -> SpotifyCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StorageError.unavailable }
        do { return try JSONDecoder().decode(SpotifyCredentials.self, from: data) }
        catch { throw StorageError.invalidData }
    }

    func save(_ credentials: SpotifyCredentials) async throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw StorageError.unavailable }
        } else if status != errSecSuccess { throw StorageError.unavailable }
    }

    func delete() async throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.unavailable }
    }

    enum StorageError: LocalizedError {
        case unavailable, invalidData
        var errorDescription: String? { "Secure credential storage could not be accessed. Unlock your iPhone and reconnect." }
    }
}
