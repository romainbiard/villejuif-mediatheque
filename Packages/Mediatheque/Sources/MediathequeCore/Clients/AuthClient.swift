// Médiathèque
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

    /// With Face ID on, the account locks again after this long in the background.
    nonisolated public static let relockDelay: TimeInterval = 120

    @ObservationIgnored private var backgroundedAt: Date?
    /// Account kept while locked again after the background: Face ID reopens it without signing in.
    @ObservationIgnored private var lockedPatron: Patron?

    @ObservationIgnored @Dependency(\.authClient) private var auth
    @ObservationIgnored @Dependency(\.date) private var date
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
            guard await biometrics.authenticate(.local("Ouvrir votre compte lecteur")) else { return }
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

    public func didEnterBackground() {
        if case .loggedIn = state { backgroundedAt = date.now }
    }

    /// Back in the foreground: past `relockDelay` with Face ID on, the account locks and asks for Face ID.
    public func didBecomeActive() async {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        guard isFaceIDEnabled, case let .loggedIn(patron) = state,
              date.now.timeIntervalSince(backgroundedAt) >= Self.relockDelay
        else { return }
        lockedPatron = patron
        state = .locked
        await unlock()
    }

    /// Asks for Face ID: at launch after a denial or cancellation, or after a relock.
    public func unlock() async {
        guard state == .locked else { return }
        if let patron = lockedPatron {
            if await biometrics.authenticate(.local("Ouvrir votre compte lecteur")) {
                lockedPatron = nil
                state = .loggedIn(patron)
            }
            return
        }
        state = .restoring
        await restore()
        if state == .restoring { state = .locked }
    }

    public func logout() async {
        lockedPatron = nil
        backgroundedAt = nil
        await auth.logout()
        await AccountSync.reset()
        isFaceIDEnabled = false
        // The next patron to sign in on this device will see the default settings again.
        defaults.removeObject(forKey: ReminderSettings.Key.onboardingDone)
        state = .loggedOut
    }
}
