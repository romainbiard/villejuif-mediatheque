// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import SwiftUI
import UIKit
import WebKit

/// Web view that runs the provider's SSO with the portal session,
/// and hands off to the native app as soon as the flow allows.
struct PortalWebView: UIViewRepresentable {
    let url: URL
    let cookies: [HTTPCookie]
    @Binding var isLoading: Bool
    @Binding var handedOffToApp: Bool

    /// Providers' known universal links: they open the app already signed in.
    /// Taken from their apple-app-site-association files.
    static func isProviderAppLink(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        if host.hasSuffix("cafeyn.co") { return path.contains("/externallogin/") }
        if host == "app.mozaik.co" { return path.hasPrefix("/autologin.php") }
        return false
    }

    /// Custom schemes of the partner apps (Médiathèque Numérique, Cafeyn, Mozaik, Louise, IZNEO).
    static let partnerAppSchemes = Set(DigitalCatalog.offers.compactMap { $0.app?.urlScheme?.lowercased() })

    /// Whether a non-web URL met in the web view may be handed to iOS.
    /// `UIApplication.open` launches any installed app (LSApplicationQueriesSchemes only limits
    /// `canOpenURL`), so a provider page, an ad or an iframe could otherwise open `sms:`,
    /// `facetime:` or another app with parameters of its choosing.
    /// - Partner app schemes: from the main frame only (the portal's redirect to the app needs no tap).
    /// - `mailto:` and `tel:`: only after the user tapped a link.
    /// - Anything else, or anything from an iframe: blocked.
    static func mayOpenExternally(_ url: URL, isMainFrame: Bool, userTapped: Bool) -> Bool {
        guard let scheme = url.scheme?.lowercased(), isMainFrame else { return false }
        if partnerAppSchemes.contains(scheme) { return true }
        return ["mailto", "tel"].contains(scheme) && userTapped
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Storage specific to this opening: the provider session does not outlive the sheet.
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
        /// Links already offered to the app: if refused, load them in the web view without looping.
        private var triedInApp: Set<URL> = []

        init(_ parent: PortalWebView) {
            self.parent = parent
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }

            // Non-web scheme: only partner apps (and mailto/tel after a tap) reach iOS, the rest is dropped.
            if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(scheme) {
                let isMainFrame = action.targetFrame?.isMainFrame ?? false
                if PortalWebView.mayOpenExternally(url, isMainFrame: isMainFrame, userTapped: action.navigationType == .linkActivated),
                   await UIApplication.shared.open(url) {
                    parent.handedOffToApp = true
                }
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
