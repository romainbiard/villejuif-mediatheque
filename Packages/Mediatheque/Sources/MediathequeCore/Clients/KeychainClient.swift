// Ma médiathèque
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

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

extension DependencyValues {
    public var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
