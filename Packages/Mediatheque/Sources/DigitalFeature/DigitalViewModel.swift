// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Session opened with a provider: the SSO URL and the portal cookies for the web view.
public struct PortalSession: Identifiable, Sendable {
    public let id = UUID()
    public let offer: DigitalOffer
    /// ⚠️ May contain personal data (Arte): never log it.
    public let url: URL
    public let cookies: [HTTPCookie]
}

/// App Store sheet to present in the app.
public struct StoreProduct: Identifiable, Equatable, Sendable {
    public let id: String
}

public enum AppAvailability: Equatable, Sendable {
    case installed
    case notInstalled
    /// No known scheme (musicMe): iOS cannot tell.
    case unknown
}

/// Where a service is used: the line under its name, in the tab.
public enum ServiceAccess: Equatable, Sendable {
    case appInstalled
    /// The app is required but not installed yet.
    case inApp
    /// Borrowed on the web, read in the named app.
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
    /// "Installer l'app" sheet, before the App Store sheet.
    public var installOffer: DigitalOffer?
    public var storeProduct: StoreProduct?
    /// The app was just installed from Ma médiathèque: "L'app est installée" banner.
    public private(set) var justInstalled: DigitalOffer.ID?
    private var installedSchemes: Set<String> = []
    /// Service whose app the patron went to get: open it as soon as it is there.
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

    /// "Connecter l'app avec ma carte" only makes sense for a required app that is already installed.
    public func canConnectApp(_ offer: DigitalOffer) -> Bool {
        access(for: offer) == .appInstalled
    }

    /// True when the primary button should offer to install rather than open.
    public func needsInstall(_ offer: DigitalOffer) -> Bool {
        guard let app = offer.app, app.role == .required else { return false }
        return availability(of: app) == .notInstalled
    }

    /// On appear and when returning to the app (App Store, Settings): apps may have changed.
    public func refreshInstalledApps() async {
        installedSchemes = Set(offers.compactMap(\.app?.urlScheme).filter { installedApps.isInstalled($0) })
        guard let pendingInstall, let offer = offers.first(where: { $0.id == pendingInstall }),
              let app = offer.app, availability(of: app) == .installed
        else { return }
        self.pendingInstall = nil
        justInstalled = offer.id
        // First launch: go through the portal so the app receives the patron's session.
        await open(offer)
        if session != nil { feedback = .success }
    }

    /// A card's primary button: install the app if missing, open it if present, otherwise the web.
    public func primaryAction(_ offer: DigitalOffer) async {
        if needsInstall(offer) {
            installOffer = offer
            feedback = .lightImpact
        } else if let app = offer.app, app.role == .required, availability(of: app) == .installed,
                  let url = app.launchURL, await installedApps.open(url) {
            // Portal sign-in does not open the app (Arte): launch the app itself, which keeps its session.
            feedback = .lightImpact
        } else {
            await open(offer)
        }
    }

    /// "Connecter l'app" (help): sign-in through the portal, for a first time or a lost session.
    public func connectThroughPortal(_ offer: DigitalOffer) async {
        await open(offer)
    }

    /// "Obtenir l'app": App Store sheet in the app, without leaving Ma médiathèque.
    public func getApp(for offer: DigitalOffer) {
        guard let app = offer.app else { return }
        installOffer = nil
        pendingInstall = offer.id
        storeProduct = StoreProduct(id: app.appStoreID)
    }

    /// "Continuer dans le navigateur": the service on the web, without the app.
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

    /// The SSO URL is single-use and short-lived: resolve it at tap time.
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
