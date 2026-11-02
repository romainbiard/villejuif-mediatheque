// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

@MainActor
@Observable
public final class LoginViewModel {
    public var cardNumber = ""
    public var password = ""
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.authClient) private var auth

    public init() {}

    public var canSubmit: Bool {
        !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    public func submit(into session: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let patron = try await auth.login(Credentials(
                cardNumber: cardNumber.trimmingCharacters(in: .whitespaces),
                password: password
            ))
            password = ""
            feedback = .success
            session.didLogIn(patron)
        } catch AuthError.invalidCredentials {
            errorMessage = String.local("Numéro de carte ou mot de passe incorrect.")
            feedback = .error
        } catch {
            errorMessage = LoadError(error) == .offline
                ? String.local("Pas de connexion. Réessayez une fois en ligne.")
                : String.local("Le site de la médiathèque ne répond pas. Réessayez dans un instant.")
            feedback = .error
        }
    }
}

@MainActor
@Observable
public final class LostPasswordViewModel {
    public enum State: Equatable { case idle, sending, sent, failed(String) }

    public var cardNumber: String
    public private(set) var state: State = .idle

    @ObservationIgnored @Dependency(\.authClient) private var auth

    public init(cardNumber: String = "") {
        self.cardNumber = cardNumber
    }

    public func send() async {
        let card = cardNumber.trimmingCharacters(in: .whitespaces)
        guard !card.isEmpty, state != .sending else { return }
        state = .sending
        do {
            try await auth.requestPasswordReset(card)
            state = .sent
        } catch {
            state = .failed(String.local("L'envoi n'a pas abouti. Réessayez, ou demandez à l'accueil d'une médiathèque."))
        }
    }
}
