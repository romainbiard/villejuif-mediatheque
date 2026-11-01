// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies
import Foundation

public enum AuthError: Error, Equatable, Sendable {
    /// The portal said so explicitly ("L'identifiant ou le mot de passe est invalide.").
    case invalidCredentials
    case notLoggedIn
    /// The form went through but no session opened, without the portal refusing the credentials:
    /// a temporary failure, never a reason to forget the stored password.
    case sessionNotOpened
}

/// Opens the web session through the form and reopens it automatically when it expires.
/// The session expires quickly: every authenticated call goes through `perform`.
public actor SessionManager {
    private let http: HTTPClient
    private let keychain: KeychainClient
    private var loginTask: Task<Patron, Error>?

    public init(http: HTTPClient, keychain: KeychainClient) {
        self.http = http
        self.keychain = keychain
    }

    /// Explicit sign-in (Sign-in screen). Credentials are only kept on success.
    @discardableResult
    public func login(_ credentials: Credentials) async throws -> Patron {
        let patron = try await openSession(credentials)
        try keychain.save(credentials)
        return patron
    }

    /// Reopens the session with the keychain credentials, `nil` if there are none.
    public func restore() async throws -> Patron? {
        guard let credentials = try keychain.load() else { return nil }
        return try await reopen(with: credentials)
    }

    /// Requests a password reset email. The form rejects a submission
    /// less than 2 s after it is displayed (`minimum_time`), hence the wait.
    public func requestPasswordReset(cardNumber: String) async throws {
        let page = try await http.string(for: .lostPasswordPage)
        let token = try HTMLParsers.csrfToken(in: page)
        try await Task.sleep(for: .seconds(2.2))
        _ = try await http.data(for: .lostPassword(cardNumber: cardNumber, csrfToken: token))
    }

    public func logout() async {
        _ = try? await http.data(for: .logout)
        await http.clearSession()
        try? keychain.delete()
    }

    /// Runs `operation`; if the session has expired, signs in again once and retries.
    public func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch BokehError.unauthorized {
            guard let credentials = try keychain.load() else { throw AuthError.notLoggedIn }
            _ = try await reopen(with: credentials)
            return try await operation()
        }
    }

    /// Only one sign-in at a time, even if several screens detect the expiry together.
    private func reopen(with credentials: Credentials) async throws -> Patron {
        if let loginTask { return try await loginTask.value }
        let task = Task { try await openSession(credentials) }
        loginTask = task
        defer { loginTask = nil }
        do {
            return try await task.value
        } catch AuthError.invalidCredentials {
            // The portal explicitly refused the stored password (changed on the website): forget it,
            // so background refreshes stop signing in with it. The patron signs in again.
            try? keychain.delete()
            throw AuthError.invalidCredentials
        }
    }

    private func openSession(_ credentials: Credentials) async throws -> Patron {
        let loginPage = try await http.string(for: .loginPage)
        let token = try HTMLParsers.csrfToken(in: loginPage)
        let response = try await http.string(for: .login(cardNumber: credentials.cardNumber, password: credentials.password, csrfToken: token))
        // Only the portal's explicit message is a refusal. No answer, a timeout or a server error
        // throws before this point and keeps the stored password.
        if (try? HTMLParsers.loginRejected(in: response)) == true {
            throw AuthError.invalidCredentials
        }
        do {
            let account = try await http.decode(AccountResponseDTO.self, from: .account).account
            return Patron(dto: account)
        } catch BokehError.unauthorized {
            throw AuthError.sessionNotOpened
        }
    }
}

extension SessionManager: DependencyKey {
    public static var liveValue: SessionManager {
        @Dependency(\.httpClient) var http
        @Dependency(\.keychainClient) var keychain
        return SessionManager(http: http, keychain: keychain)
    }
}

extension DependencyValues {
    public var sessionManager: SessionManager {
        get { self[SessionManager.self] }
        set { self[SessionManager.self] = newValue }
    }
}
