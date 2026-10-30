#if os(iOS)
import SwiftUI
import UIKit
import WebKit

/// Vue web qui déroule le SSO du fournisseur avec la session du portail,
/// et passe la main à l'app native dès que le parcours le permet.
struct PortalWebView: UIViewRepresentable {
    let url: URL
    let cookies: [HTTPCookie]
    @Binding var isLoading: Bool
    @Binding var handedOffToApp: Bool

    /// Universal links connus des fournisseurs : ils ouvrent l'app déjà connectée.
    /// Relevés dans leurs fichiers apple-app-site-association.
    static func isProviderAppLink(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        if host.hasSuffix("cafeyn.co") { return path.contains("/externallogin/") }
        if host == "app.mozaik.co" { return path.hasPrefix("/autologin.php") }
        return false
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Stockage propre à cette ouverture : la session fournisseur ne survit pas à la feuille.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        let store = configuration.websiteDataStore.httpCookieStore
        let request = URLRequest(url: url)
        Task { @MainActor in
            for cookie in cookies { await store.setCookie(cookie) }
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PortalWebView
        /// Liens déjà proposés à l'app : en cas de refus, on les charge dans la vue web sans reboucler.
        private var triedInApp: Set<URL> = []

        init(_ parent: PortalWebView) {
            self.parent = parent
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }

            // Scheme propre à une app (médiathèque numérique, musicMe…) : on le confie à iOS.
            if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(scheme) {
                if await UIApplication.shared.open(url) { parent.handedOffToApp = true }
                return .cancel
            }

            if PortalWebView.isProviderAppLink(url), !triedInApp.contains(url) {
                triedInApp.insert(url)
                if await UIApplication.shared.open(url, options: [.universalLinksOnly: true]) {
                    parent.handedOffToApp = true
                    return .cancel
                }
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
#endif
