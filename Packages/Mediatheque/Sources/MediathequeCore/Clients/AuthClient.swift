import Dependencies
import DependenciesMacros
import Foundation
import Observation

/// Façade testable de `SessionManager` pour les ViewModels.
@DependencyClient
public struct AuthClient: Sendable {
    public var login: @Sendable (_ credentials: Credentials) async throws -> Patron
    /// Rouvre la session avec le trousseau ; `nil` si aucun identifiant n'est enregistré.
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

/// État de connexion partagé par toute l'app (onglet Compte, réservation depuis une fiche).
/// Créé une fois par l'app et transmis par `.environment(sessionStore)`.
@MainActor
@Observable
public final class SessionStore {
    public enum State: Equatable, Sendable {
        case restoring
        /// Face ID est activé et n'a pas encore été validé.
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

    /// Au lancement : rouvre la session si des identifiants sont dans le trousseau.
    public func restore() async {
        let hasCredentials = (try? keychain.load()) != nil
        if hasCredentials, isFaceIDEnabled {
            state = .locked
            guard await biometrics.authenticate("Ouvrir votre compte lecteur") else { return }
        }
        do {
            state = (try await auth.restore()).map(State.loggedIn) ?? .loggedOut
        } catch {
            // Hors ligne au lancement : on reste déconnecté, la prochaine action réessaiera.
            state = .loggedOut
        }
    }

    public func didLogIn(_ patron: Patron) {
        state = .loggedIn(patron)
    }

    /// Rafraîchit la fiche (compteurs, carte) après une action.
    public func update(_ patron: Patron) {
        if case .loggedIn = state { state = .loggedIn(patron) }
    }

    /// Nouvel essai après un Face ID refusé ou annulé.
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
        // Le prochain abonné qui se connecte sur cet appareil reverra les réglages de départ.
        defaults.removeObject(forKey: ReminderSettings.Key.onboardingDone)
        state = .loggedOut
    }
}
