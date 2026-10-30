import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import DigitalFeature

@MainActor
struct DigitalTests {
    @Test func providerUniversalLinksAreRecognised() {
        #expect(PortalWebView.isProviderAppLink(URL(string: "https://www.cafeyn.co/fr/externallogin/abc")!))
        #expect(!PortalWebView.isProviderAppLink(URL(string: "https://www.cafeyn.co/fr/loginexternal/8480")!))
        #expect(PortalWebView.isProviderAppLink(URL(string: "https://app.mozaik.co/autoLogin.php?t=1")!))
        #expect(!PortalWebView.isProviderAppLink(URL(string: "https://vod.mediatheque-numerique.com/")!))
    }

    @Test func openingResolvesTheSSOTarget() async {
        let viewModel = withDependencies {
            $0.digitalClient.target = { service in
                #expect(service == .cafeyn)
                return URL(string: "https://www.cafeyn.co/fr/loginexternal/8480")!
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
