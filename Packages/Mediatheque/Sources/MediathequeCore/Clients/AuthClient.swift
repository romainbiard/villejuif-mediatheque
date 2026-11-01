// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation
import Observation

/// Testable facade over `SessionManager` for the ViewModels.
@DependencyClient
public struct AuthClient: Sendable {
    public var login: @Sendable (_ credentials: Credentials) async throws -> Patron
    /// Reopens the session from the keychain; `nil` if no credentials are saved.
    public var restore: @Sendable () async throws -> Patron?
    public var logout: @Sendable () async -> Void
    public var requestPasswordReset: @Sendable (_ cardNumber: String) async throws -> Void
}

extension AuthClient: DependencyKey {
    public static var liveValue: AuthClient {
        @Dependency(\.sessionManager) var session
        return AuthClient(
            login: { try await session.login($0) },
            restore: { try await session.restore() },
            logout: { await session.logout() },
            requestPasswordReset: { try await session.requestPasswordReset(cardNumber: $0) }
        )
    }

    public static let previewValue = AuthClient(
        login: { _ in SampleData.patron },
        restore: { SampleData.patron },
        logout: {},
        requestPasswordReset: { _ in }
    )

    public static let testValue = AuthClient()
}

extension DependencyValues {
    public var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

/// Sign-in state shared across the app (Account tab, hold from a record page).
/// Created once by the app and passed down via `.environment(sessionStore)`.
@MainActor
@Observable
public final class SessionStore {
    public enum State: Equatable, Sendable {
        case restoring
        /// Face ID is enabled and hasn't been passed yet.
        case locked
        case loggedOut
        case loggedIn(Patron)
    }

    public private(set) var state: State = .restoring

    @ObservationIgnored @Dependency(\.authClient) private var auth
    @ObservationIgnored @Dependency(\.biometricClient) private var biometrics
    @ObservationIgnored @Dependency(\.keychainClient) private var keychain
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .shared) {
        self.defaults = defaults
    }

    public var isFaceIDEnabled: Bool {
        get { defaults.bool(forKey: ReminderSettings.Key.faceID) }
        set { defaults.set(newValue, forKey: ReminderSettings.Key.faceID) }
    }

    public var patron: Patron? {
        if case let .loggedIn(patron) = state { return patron }
        return nil
    }

    /// At launch: reopens the session if credentials are in the keychain.
    public func restore() async {
        let hasCredentials = (try? keychain.load()) != nil
        if hasCredentials, isFaceIDEnabled {
            state = .locked
            guard await biometrics.authenticate("Ouvrir votre compte lecteur") else { return }
        }
        do {
            state = (try await auth.restore()).map(State.loggedIn) ?? .loggedOut
        } catch {
            // Offline at launch: stay signed out, the next action will retry.
            state = .loggedOut
        }
    }

    public func didLogIn(_ patron: Patron) {
        state = .loggedIn(patron)
    }

    /// Refreshes the account (counters, card) after an action.
    public func update(_ patron: Patron) {
        if case .loggedIn = state { state = .loggedIn(patron) }
    }

    /// Retries after Face ID was denied or cancelled.
    public func unlock() async {
        guard state == .locked else { return }
        state = .restoring
        await restore()
        if state == .restoring { state = .locked }
    }

    public func logout() async {
        await auth.logout()
        await AccountSync.reset()
        isFaceIDEnabled = false
        // The next patron to sign in on this device will see the default settings again.
        defaults.removeObject(forKey: ReminderSettings.Key.onboardingDone)
        state = .loggedOut
    }
}
