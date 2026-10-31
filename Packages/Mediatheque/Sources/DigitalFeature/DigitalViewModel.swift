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

/// Fiche App Store à présenter dans l'app.
public struct StoreProduct: Identifiable, Equatable, Sendable {
    public let id: String
}

public enum AppAvailability: Equatable, Sendable {
    case installed
    case notInstalled
    /// Pas de scheme connu (musicMe) : iOS ne peut pas le dire.
    case unknown
}

/// Où se consulte un service : la ligne sous son nom, dans l'onglet.
public enum ServiceAccess: Equatable, Sendable {
    case appInstalled
    /// L'app est nécessaire mais pas encore installée.
    case inApp
    /// Emprunt sur le web, lecture dans l'app nommée.
    case reader(String)
    case web
}

@MainActor
@Observable
public final class DigitalViewModel {
    public let offers = DigitalCatalog.offers
    public private(set) var resolving: DigitalOffer.ID?
    public var session: PortalSession?
    public private(set) var errorMessage: String?
    public private(set) var feedback: FeedbackEvent?
    /// Feuille « Installer l'app », avant la fiche App Store.
    public var installOffer: DigitalOffer?
    public var storeProduct: StoreProduct?
    /// L'app vient d'être installée depuis Ma médiathèque : bannière « L'app est installée ».
    public private(set) var justInstalled: DigitalOffer.ID?
    private var installedSchemes: Set<String> = []
    /// Service dont l'abonné est allé chercher l'app : on l'ouvre dès qu'elle est là.
    private var pendingInstall: DigitalOffer.ID?

    @ObservationIgnored @Dependency(\.digitalClient) private var digital
    @ObservationIgnored @Dependency(\.installedApps) private var installedApps

    public init() {}

    public func availability(of app: ProviderApp) -> AppAvailability {
        guard let scheme = app.urlScheme else { return .unknown }
        return installedSchemes.contains(scheme) ? .installed : .notInstalled
    }

    public func access(for offer: DigitalOffer) -> ServiceAccess {
        guard let app = offer.app else { return .web }
        switch app.role {
        case .required: return availability(of: app) == .installed ? .appInstalled : .inApp
        case .reader: return .reader(app.name)
        case .companion: return .web
        }
    }

    /// « Connecter l'app avec ma carte » n'a de sens que pour une app nécessaire déjà installée.
    public func canConnectApp(_ offer: DigitalOffer) -> Bool {
        access(for: offer) == .appInstalled
    }

    /// Vrai quand le bouton principal doit proposer l'installation plutôt que l'ouverture.
    public func needsInstall(_ offer: DigitalOffer) -> Bool {
        guard let app = offer.app, app.role == .required else { return false }
        return availability(of: app) == .notInstalled
    }

    /// À l'affichage et au retour dans l'app (App Store, Réglages) : les apps ont pu changer.
    public func refreshInstalledApps() async {
        installedSchemes = Set(offers.compactMap(\.app?.urlScheme).filter { installedApps.isInstalled($0) })
        guard let pendingInstall, let offer = offers.first(where: { $0.id == pendingInstall }),
              let app = offer.app, availability(of: app) == .installed
        else { return }
        self.pendingInstall = nil
        justInstalled = offer.id
        // Première ouverture : on passe par le portail pour que l'app reçoive la session de l'abonné.
        await open(offer)
        if session != nil { feedback = .success }
    }

    /// Bouton principal d'une carte : installer l'app si elle manque, l'ouvrir si elle est là, sinon le web.
    public func primaryAction(_ offer: DigitalOffer) async {
        if needsInstall(offer) {
            installOffer = offer
            feedback = .lightImpact
        } else if let app = offer.app, app.role == .required, availability(of: app) == .installed,
                  let url = app.launchURL, await installedApps.open(url) {
            // La connexion du portail n'ouvre pas l'app (Arte) : on lance l'app elle-même, qui garde sa session.
            feedback = .lightImpact
        } else {
            await open(offer)
        }
    }

    /// « Connecter l'app » (aide) : la connexion par le portail, pour une première fois ou une session perdue.
    public func connectThroughPortal(_ offer: DigitalOffer) async {
        await open(offer)
    }

    /// « Obtenir l'app » : fiche App Store dans l'app, sans quitter Ma médiathèque.
    public func getApp(for offer: DigitalOffer) {
        guard let app = offer.app else { return }
        installOffer = nil
        pendingInstall = offer.id
        storeProduct = StoreProduct(id: app.appStoreID)
    }

    /// « Continuer dans le navigateur » : le service sur le web, sans l'app.
    public func continueOnWeb(_ offer: DigitalOffer) async {
        installOffer = nil
        await open(offer)
    }

    public func storeDismissed() async {
        storeProduct = nil
        await refreshInstalledApps()
    }

    public func dismissInstalledBanner() {
        justInstalled = nil
    }

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
