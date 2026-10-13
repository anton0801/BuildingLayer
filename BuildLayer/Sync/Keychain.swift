//
//  Keychain.swift
//  BuildLayer
//
//  Credentials live in the Keychain, never UserDefaults.
//
//  UserDefaults is a plist in the app container: readable from a backup, from a
//  jailbroken device, and from anything with file access. The install secret is
//  the only proof of account ownership this anonymous design has, so losing it
//  means losing the account — and leaking it means handing it over.
//

import Foundation
import Security

enum KeychainStore {

    enum Key: String {
        case installSecret = "buildlayer.install_secret"
        case accessToken   = "buildlayer.access_token"
        case refreshToken  = "buildlayer.refresh_token"
        case deviceID      = "buildlayer.device_id"
    }

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        // Update in place when it already exists — SecItemAdd fails with
        // errSecDuplicateItem rather than overwriting.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var insert = query
        insert[kSecValueData as String] = data
        // Never migrates to a new device in a backup, and is unreadable while
        // the device is locked. The account is tied to this install by design.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    @discardableResult
    static func remove(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func removeAll() {
        for key in [Key.installSecret, .accessToken, .refreshToken, .deviceID] {
            remove(key)
        }
    }

    /// The install secret, generated once and reused for the life of the install.
    static func installSecret() -> String {
        if let existing = get(.installSecret), existing.count >= 64 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        // SecRandomCopyBytes rather than any arithmetic RNG: this value is the
        // account credential.
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        set(secret, for: .installSecret)
        return secret
    }
}
