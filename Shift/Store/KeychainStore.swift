//
//  KeychainStore.swift
//  Shift
//

import Foundation
import Security

/// Minimal Keychain wrapper for the user's Anthropic API key.
///
/// The key is a long-lived credential that can spend the user's money, so it
/// belongs in the Keychain rather than `UserDefaults` — the latter is plain
/// plist on disk and is included in unencrypted backups.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps it off iCloud
/// Keychain and out of device backups entirely: it is the user's own secret and
/// there is no reason for it to leave the device it was typed on.
enum KeychainStore {
    private static let service = "com.desalas.Shift.anthropic"
    private static let account = "apiKey"

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return message ?? String(localized: "Keychain error \(Int(status)).")
            }
        }
    }

    static func save(apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey()
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        let addStatus = SecItemAdd(query.merging(attributes) { current, _ in current } as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static var hasAPIKey: Bool { loadAPIKey() != nil }
}
