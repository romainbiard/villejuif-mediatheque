// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Digital services: each `/modules/{slug}` returns the provider's SSO URL.
public enum DigitalService: String, CaseIterable, Sendable, Identifiable {
    case arteVod = "arte-vod"
    case cafeyn
    case izneo = "cvs2"
    case numilog
    case toutApprendre = "tout-apprendre"
    case eureka = "bibliondemand"

    public var id: String { rawValue }

    /// True when the provider URL calls back the portal: the web session is then required
    /// (WKWebView with the cookie), not plain Safari.
    public var needsPortalSession: Bool {
        switch self {
        case .cafeyn, .eureka: true
        case .arteVod, .izneo, .numilog, .toutApprendre: false
        }
    }
}

@DependencyClient
public struct DigitalClient: Sendable {
    /// SSO URL, single-use and short-lived: resolve it at tap time, never in advance.
    /// ⚠️ It may contain personal data (Arte): never log it.
    public var target: @Sendable (_ service: DigitalService) async throws -> URL
    /// Web session cookies, to inject into a `WKWebView`.
    public var sessionCookies: @Sendable () async -> [HTTPCookie] = { [] }
}

extension DigitalClient: DependencyKey {
    public static var liveValue: DigitalClient {
        @Dependency(\.httpClient) var http
        @Dependency(\.sessionManager) var session
        return DigitalClient(
            target: { service in
                try await session.perform {
                    let page = try await http.string(for: .digitalModule(service.rawValue))
                    guard let url = HTMLParsers.ssoTarget(in: page) else {
                        throw BokehError.unexpectedFormat("URL SSO introuvable pour \(service.rawValue)")
                    }
                    return url
                }
            },
            sessionCookies: { await http.sessionCookies() }
        )
    }

    public static let previewValue = DigitalClient(
        target: { _ in URL(string: "https://vod.mediatheque-numerique.com/")! },
        sessionCookies: { [] }
    )

    public static let testValue = DigitalClient()
}

extension DependencyValues {
    public var digitalClient: DigitalClient {
        get { self[DigitalClient.self] }
        set { self[DigitalClient.self] = newValue }
    }
}
