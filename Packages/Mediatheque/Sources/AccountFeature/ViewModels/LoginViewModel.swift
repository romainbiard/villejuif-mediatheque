// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var cardNumber = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.authClient) private var auth

    init() {}

    var canSubmit: Bool {
        !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    func submit(into session: SessionStore) async {
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
final class LostPasswordViewModel {
    enum State: Equatable { case idle, sending, sent, failed(String) }

    var cardNumber: String
    private(set) var state: State = .idle

    @ObservationIgnored @Dependency(\.authClient) private var auth

    init(cardNumber: String = "") {
        self.cardNumber = cardNumber
    }

    func send() async {
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
