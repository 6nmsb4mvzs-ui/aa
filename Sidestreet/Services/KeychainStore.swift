import Foundation
import Security

/// Stores the optional YouTube API key in the device Keychain (never in
/// source code, UserDefaults or backups that leave the device unencrypted).
enum KeychainStore {
    private static let service = "app.sidestreet.credentials"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static var mapillaryToken: String? {
        get { string(for: "mapillary.token") }
        set { set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: "mapillary.token") }
    }

    static var youTubeAPIKey: String? {
        get { string(for: "youtube.apiKey") }
        set { set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: "youtube.apiKey") }
    }
}
