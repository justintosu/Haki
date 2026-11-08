//
//  HevyKeychain.swift
//  Haki
//
//  The person's Hevy API key, kept in this iPhone's Keychain (never in
//  UserDefaults, never synced to iCloud, never logged). Only
//  `HevySyncService` reads it.
//

import Foundation
import Security

nonisolated enum HevyKeychain {
    private static let service = "app.haki.hevy"
    private static let account = "api-key"

    /// The saved API key, or nil when Hevy isn't connected.
    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// Saves (or replaces) the API key. Readable after the first unlock,
    /// on this device only.
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw HevyKeychainError(status: updateStatus)
        }

        var item = baseQuery()
        for (name, value) in attributes {
            item[name] = value
        }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw HevyKeychainError(status: addStatus)
        }
    }

    /// Removes the API key (disconnecting). Does nothing if there is none.
    static func delete() {
        _ = SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The Keychain refused to store the key.
nonisolated struct HevyKeychainError: LocalizedError, Equatable {
    var status: OSStatus

    var errorDescription: String? {
        "Haki couldn't save the API key on this iPhone (Keychain error \(status)). Try again."
    }
}
