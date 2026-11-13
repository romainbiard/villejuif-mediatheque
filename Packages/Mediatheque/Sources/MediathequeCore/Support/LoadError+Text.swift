// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// What a screen says about a `LoadError`. Text only: the views come from `DesignSystem`.
extension LoadError {
    public var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .notLoggedIn: "lock"
        case .siteUnavailable, .unreadableAnswer, .other: "exclamationmark.triangle"
        }
    }

    /// Error screen title, when there is nothing to show yet.
    public var title: String {
        switch self {
        case .offline: .local("Pas de connexion")
        case .notLoggedIn: .local("Session fermée")
        case .siteUnavailable, .other: .local("Le site de la médiathèque ne répond pas")
        case .unreadableAnswer: .local("Réponse inattendue du site")
        }
    }

    public var message: String {
        switch self {
        case .offline: .local("Vérifiez votre connexion, puis réessayez.")
        case .notLoggedIn: .local("Reconnectez-vous pour continuer.")
        case .siteUnavailable, .other: .local("Réessayez dans un instant.")
        case .unreadableAnswer: .local("Le site a répondu, mais l'app ne sait pas encore lire sa réponse. Réessayez plus tard.")
        }
    }

    /// Short line above cached data: "Hors ligne", "Mise à jour impossible"…
    public var staleText: String {
        switch self {
        case .offline: .local("Hors ligne · dernières données enregistrées")
        default: .local("Mise à jour impossible · dernières données enregistrées")
        }
    }

    public var staleSystemImage: String {
        switch self {
        case .offline: "wifi.slash"
        default: "icloud.slash"
        }
    }
}
