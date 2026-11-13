// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import WebKit

/// The portal sits behind BunkerWeb, whose "antibot" redirects unknown clients to `/challenge`:
/// a JavaScript proof of work that submits itself and, once solved, sets a clearance cookie.
/// `URLSession` can't run it, so we let an offscreen `WKWebView` solve it and hand its cookies back.
public enum BunkerWebChallenge {
    public static let path = "/challenge"

    /// Loads `url` in an offscreen web view until BunkerWeb lets it leave `/challenge`,
    /// then returns the cookies the web view holds for the portal.
    ///
    /// `cookies` seed the web view (so an open `PHPSESSID` survives the round trip) and `userAgent`
    /// must match `URLSession`'s: BunkerWeb ties its session to the user agent.
    @MainActor
    public static func solve(
        url: URL,
        userAgent: String,
        cookies: [HTTPCookie],
        timeout: Duration = .seconds(30)
    ) async throws -> [HTTPCookie] {
        let solver = Solver(userAgent: userAgent)
        return try await solver.solve(url: url, cookies: cookies, timeout: timeout)
    }

    @MainActor
    private final class Solver: NSObject, WKNavigationDelegate {
        private let webView: WKWebView
        private var continuation: CheckedContinuation<Void, Error>?

        init(userAgent: String) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            webView.customUserAgent = userAgent
            super.init()
            webView.navigationDelegate = self
        }

        func solve(url: URL, cookies: [HTTPCookie], timeout: Duration) async throws -> [HTTPCookie] {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in cookies {
                await store.setCookie(cookie)
            }

            let timeoutTask = Task { [weak self] in
                try await Task.sleep(for: timeout)
                self?.finish(.failure(BokehError.challengeFailed))
            }
            defer {
                timeoutTask.cancel()
                webView.stopLoading()
            }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.load(URLRequest(url: url))
            }

            let host = url.host() ?? ""
            return await store.allCookies().filter { cookie in
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }
        }

        private func finish(_ result: Result<Void, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            // The clearance cookie came with the redirect out of `/challenge`:
            // no need to load the page the challenge was guarding.
            guard navigationResponse.isForMainFrame,
                  let path = navigationResponse.response.url?.path(),
                  path != BunkerWebChallenge.path
            else { return .allow }
            finish(.success(()))
            return .cancel
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail(with: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fail(with: error)
        }

        private func fail(with error: any Error) {
            // The challenge's own form submission interrupts the page load: not a failure.
            if (error as NSError).code == NSURLErrorCancelled { return }
            finish(.failure(BokehError.challengeFailed))
        }
    }
}
