// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import DigitalFeature

/// A URL written out in a test: always valid.
private func url(_ string: String) -> URL {
    URL(string: string)!
}

/// A service of the catalog, by its identifier (the catalog is static).
private func offer(_ id: String) -> DigitalOffer {
    DigitalCatalog.offers.first { $0.id == id }!
}

@MainActor
struct DigitalTests {
    @Test func providerUniversalLinksAreRecognised() {
        #expect(PortalWebView.isProviderAppLink(url("https://www.cafeyn.co/fr/externallogin/abc")))
        #expect(!PortalWebView.isProviderAppLink(url("https://www.cafeyn.co/fr/loginexternal/8480")))
        #expect(PortalWebView.isProviderAppLink(url("https://app.mozaik.co/autoLogin.php?t=1")))
        #expect(!PortalWebView.isProviderAppLink(url("https://vod.mediatheque-numerique.com/")))
    }

    @Test func onlyPartnerAppsLeaveTheWebView() {
        let open = { (url: String, mainFrame: Bool, tapped: Bool) in
            PortalWebView.mayOpenExternally(URL(string: url)!, isMainFrame: mainFrame, userTapped: tapped)
        }
        // Partner apps: from the main frame, even without a tap (the portal's redirect to the app).
        #expect(open("arte-mednum://login?token=x", true, false))
        #expect(open("cafeyn://home", true, false))
        // Never from an iframe.
        #expect(!open("arte-mednum://login", false, true))
        // Other apps and system schemes are dropped, tapped or not.
        #expect(!open("sms:+33600000000&body=hello", true, true))
        #expect(!open("facetime:someone@example.org", true, true))
        #expect(!open("itms-apps://apps.apple.com/app/id1", true, true))
        #expect(!open("otherapp://do-something", true, false))
        // mailto and tel only after a tap on a link.
        #expect(open("mailto:contact@example.org", true, true))
        #expect(!open("mailto:contact@example.org", true, false))
        #expect(!open("tel:0100000000", true, false))
    }

    @Test func openingResolvesTheSSOTarget() async {
        let viewModel = withDependencies {
            $0.digitalClient.target = { service in
                #expect(service == .cafeyn)
                return url("https://www.cafeyn.co/fr/loginexternal/8480")
            }
            $0.digitalClient.sessionCookies = { [] }
        } operation: { DigitalViewModel() }

        await viewModel.open(DigitalCatalog.offers[1])
        #expect(viewModel.session?.url.host() == "www.cafeyn.co")
        #expect(viewModel.resolving == nil)
    }

    @Test func notLoggedInIsExplained() async {
        let viewModel = withDependencies {
            $0.digitalClient.target = { _ in throw AuthError.notLoggedIn }
        } operation: { DigitalViewModel() }

        await viewModel.open(DigitalCatalog.offers[0])
        #expect(viewModel.session == nil)
        #expect(viewModel.errorMessage == "Connectez-vous dans l'onglet Compte pour accéder au numérique.")
        #expect(viewModel.feedback == .error)
    }
}

@MainActor
struct PartnerAppsTests {
    private let films = offer("films")
    private let presse = offer("presse")
    private let eureka = offer("eureka")

    @Test func schemesTellWhichAppsAreInstalled() async throws {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "cafeyn" }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        let cafeyn = try #require(presse.app)
        let arte = try #require(films.app)
        let musicMe = try #require(eureka.app)
        #expect(viewModel.availability(of: cafeyn) == .installed)
        #expect(viewModel.availability(of: arte) == .notInstalled)
        // musicMe has no scheme: we cannot know.
        #expect(viewModel.availability(of: musicMe) == .unknown)
        #expect(viewModel.needsInstall(films))
        #expect(!viewModel.needsInstall(presse))
        #expect(!viewModel.needsInstall(eureka))
    }

    @Test func eachServiceSaysWhereItIsUsed() async {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "arte-mednum" }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        let byID = Dictionary(uniqueKeysWithValues: DigitalCatalog.offers.map { ($0.id, viewModel.access(for: $0)) })
        #expect(byID["films"] == .appInstalled)
        #expect(byID["presse"] == .inApp)
        #expect(byID["ebooks"] == .reader("Louise Reader"))
        #expect(byID["bd"] == .web)
        #expect(byID["eureka"] == .web)
        // "Connecter l'app" only for a required app that is already installed.
        #expect(viewModel.canConnectApp(films))
        #expect(!viewModel.canConnectApp(presse))
    }

    @Test func missingRequiredAppOffersInstallInsteadOfOpening() async {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { _ in false }
            $0.digitalClient.target = { _ in
                Issue.record("Pas de SSO tant que l'app n'est pas installée")
                return url("https://example.org")
            }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        await viewModel.primaryAction(films)
        #expect(viewModel.installOffer == films)
        #expect(viewModel.session == nil)

        viewModel.getApp(for: films)
        #expect(viewModel.installOffer == nil)
        #expect(viewModel.storeProduct == StoreProduct(id: "1562009751"))
    }

    @Test func installedAppOpensDirectly() async {
        let opened = LockIsolated<[URL]>([])
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "arte-mednum" }
            $0.installedApps.open = { url in
                opened.withValue { $0.append(url) }
                return true
            }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        await viewModel.primaryAction(films)
        #expect(opened.value == [url("arte-mednum://")])
        #expect(viewModel.installOffer == nil)
        // No portal web view: the app itself opens.
        #expect(viewModel.session == nil)
    }

    @Test func appThatRefusesToOpenFallsBackToTheWeb() async {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "arte-mednum" }
            $0.installedApps.open = { _ in false }
            $0.digitalClient.target = { _ in URL(string: "https://portal.mediatheque-numerique.com/sso_login")! }
            $0.digitalClient.sessionCookies = { [] }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        await viewModel.primaryAction(films)
        #expect(viewModel.session?.offer == films)
    }

    @Test func portalConnectionStaysAvailableForAnInstalledApp() async {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "arte-mednum" }
            $0.digitalClient.target = { _ in URL(string: "https://portal.mediatheque-numerique.com/sso_login")! }
            $0.digitalClient.sessionCookies = { [] }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        await viewModel.connectThroughPortal(films)
        #expect(viewModel.session?.offer == films)
    }

    @Test func returningFromTheStoreWithTheAppConnectsIt() async {
        let installed = LockIsolated(false)
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { $0 == "arte-mednum" && installed.value }
            $0.digitalClient.target = { _ in URL(string: "https://portal.mediatheque-numerique.com/sso_login")! }
            $0.digitalClient.sessionCookies = { [] }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        viewModel.getApp(for: films)

        // Came back without installing: nothing opens.
        await viewModel.storeDismissed()
        #expect(viewModel.session == nil)
        #expect(viewModel.justInstalled == nil)

        // Installed while the patron was in the App Store.
        viewModel.getApp(for: films)
        installed.setValue(true)
        await viewModel.storeDismissed()
        #expect(viewModel.storeProduct == nil)
        #expect(viewModel.justInstalled == "films")
        #expect(viewModel.session?.offer == films)
        #expect(viewModel.feedback == .success)
    }

    @Test func webRemainsAvailableWithoutTheApp() async {
        let viewModel = withDependencies {
            $0.installedApps.isInstalled = { _ in false }
            $0.digitalClient.target = { _ in URL(string: "https://portal.mediatheque-numerique.com/sso_login")! }
            $0.digitalClient.sessionCookies = { [] }
        } operation: { DigitalViewModel() }

        await viewModel.refreshInstalledApps()
        await viewModel.primaryAction(films)
        await viewModel.continueOnWeb(films)
        #expect(viewModel.installOffer == nil)
        #expect(viewModel.session?.offer == films)
    }
}
