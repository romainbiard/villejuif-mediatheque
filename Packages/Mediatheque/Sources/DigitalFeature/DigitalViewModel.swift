import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Session ouverte chez un fournisseur : l'URL SSO et les cookies du portail pour la vue web.
public struct PortalSession: Identifiable, Sendable {
    public let id = UUID()
    public let offer: DigitalOffer
    /// ⚠️ Peut contenir des données personnelles (Arte) : ne jamais la journaliser.
    public let url: URL
    public let cookies: [HTTPCookie]
}

@MainActor
@Observable
public final class DigitalViewModel {
    public let offers = DigitalCatalog.offers
    public private(set) var resolving: DigitalOffer.ID?
    public var session: PortalSession?
    public private(set) var errorMessage: String?
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.digitalClient) private var digital

    public init() {}

    /// L'URL SSO est à usage unique et de courte durée : on la résout au moment du tap.
    public func open(_ offer: DigitalOffer) async {
        guard resolving == nil else { return }
        resolving = offer.id
        errorMessage = nil
        defer { resolving = nil }
        do {
            let url = try await digital.target(offer.module)
            let cookies = await digital.sessionCookies()
            session = PortalSession(offer: offer, url: url, cookies: cookies)
            feedback = .lightImpact
        } catch {
            errorMessage = switch LoadError(error) {
            case .notLoggedIn: "Connectez-vous dans l'onglet Compte pour accéder au numérique."
            case .offline: "Pas de connexion. Réessayez une fois en ligne."
            default: "\(offer.provider) n'a pas pu être ouvert. Réessayez dans un instant."
            }
            feedback = .error
        }
    }

    public func dismissError() {
        errorMessage = nil
    }
}
