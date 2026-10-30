import BokehAPI
import Dependencies
import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case notLoggedIn
}

/// Ouvre la session web par le formulaire et la rouvre seule quand elle expire.
/// La session expire vite : chaque appel authentifié passe par `perform`.
public actor SessionManager {
    private let http: HTTPClient
    private let keychain: KeychainClient
    private var loginTask: Task<Patron, Error>?

    public init(http: HTTPClient, keychain: KeychainClient) {
        self.http = http
        self.keychain = keychain
    }

    /// Connexion explicite (écran Connexion). Les identifiants ne sont gardés qu'en cas de succès.
    @discardableResult
    public func login(_ credentials: Credentials) async throws -> Patron {
        let patron = try await openSession(credentials)
        try keychain.save(credentials)
        return patron
    }

    /// Rouvre la session avec les identifiants du trousseau, `nil` s'il n'y en a pas.
    public func restore() async throws -> Patron? {
        guard let credentials = try keychain.load() else { return nil }
        return try await reopen(with: credentials)
    }

    /// Demande d'e-mail de réinitialisation. Le formulaire refuse un envoi
    /// moins de 2 s après son affichage (`minimum_time`), d'où l'attente.
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

    /// Exécute `operation` ; si la session a expiré, se reconnecte une fois et rejoue.
    public func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch BokehError.unauthorized {
            guard let credentials = try keychain.load() else { throw AuthError.notLoggedIn }
            _ = try await reopen(with: credentials)
            return try await operation()
        }
    }

    /// Une seule connexion à la fois, même si plusieurs écrans détectent l'expiration ensemble.
    private func reopen(with credentials: Credentials) async throws -> Patron {
        if let loginTask { return try await loginTask.value }
        let task = Task { try await openSession(credentials) }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func openSession(_ credentials: Credentials) async throws -> Patron {
        let loginPage = try await http.string(for: .loginPage)
        let token = try HTMLParsers.csrfToken(in: loginPage)
        _ = try await http.data(for: .login(cardNumber: credentials.cardNumber, password: credentials.password, csrfToken: token))
        do {
            let account = try await http.decode(AccountResponseDTO.self, from: .account).account
            return Patron(dto: account)
        } catch BokehError.unauthorized {
            throw AuthError.invalidCredentials
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
