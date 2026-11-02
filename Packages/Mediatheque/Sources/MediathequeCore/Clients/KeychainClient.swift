// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation
import Security

public struct Credentials: Hashable, Sendable, Codable {
    public let cardNumber: String
    public let password: String

    public init(cardNumber: String, password: String) {
        self.cardNumber = cardNumber
        self.password = password
    }
}

/// Patron credentials in the keychain, to sign back in automatically when the session expires.
@DependencyClient
public struct KeychainClient: Sendable {
    public var load: @Sendable () throws -> Credentials?
    public var save: @Sendable (_ credentials: Credentials) throws -> Void
    public var delete: @Sendable () throws -> Void
}

extension KeychainClient: DependencyKey {
    static let service = "fr.villejuif.mediatheques.credentials"

    public static let liveValue = KeychainClient(
        load: {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
            return try JSONDecoder().decode(Credentials.self, from: data)
        },
        save: { credentials in
            let data = try JSONEncoder().encode(credentials)
            SecItemDelete(baseQuery as CFDictionary)
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        },
        delete: {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }
    )

    public static let previewValue: KeychainClient = {
        let stored = LockIsolated<Credentials?>(nil)
        return KeychainClient(
            load: { stored.value },
            save: { credentials in stored.setValue(credentials) },
            delete: { stored.setValue(nil) }
        )
    }()

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "abonne",
        ]
    }
}

/// Last account read from the portal, in the keychain next to the credentials: at launch the Account tab
/// shows it at once, while the web session reopens (three requests to the portal).
public struct PatronCacheClient: Sendable {
    public var load: @Sendable () -> Patron?
    public var save: @Sendable (_ patron: Patron) -> Void
    public var clear: @Sendable () -> Void

    public init(
        load: @escaping @Sendable () -> Patron?,
        save: @escaping @Sendable (_ patron: Patron) -> Void,
        clear: @escaping @Sendable () -> Void
    ) {
        self.load = load
        self.save = save
        self.clear = clear
    }
}

extension PatronCacheClient: DependencyKey {
    public static let liveValue = PatronCacheClient(
        load: {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return try? JSONDecoder().decode(Patron.self, from: data)
        },
        save: { patron in
            guard let data = try? JSONEncoder().encode(patron) else { return }
            SecItemDelete(baseQuery as CFDictionary)
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        },
        clear: { SecItemDelete(baseQuery as CFDictionary) }
    )

    public static let previewValue = PatronCacheClient(load: { nil }, save: { _ in }, clear: {})
    /// A cache that stays empty: tests opt in by overriding `load`.
    public static let testValue = previewValue

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainClient.service,
            kSecAttrAccount as String: "fiche",
        ]
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

extension DependencyValues {
    public var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }

    public var patronCache: PatronCacheClient {
        get { self[PatronCacheClient.self] }
        set { self[PatronCacheClient.self] = newValue }
    }
}
