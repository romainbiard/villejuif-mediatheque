import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Services numériques : chaque `/modules/{slug}` renvoie l'URL SSO du fournisseur.
public enum DigitalService: String, CaseIterable, Sendable, Identifiable {
    case arteVod = "arte-vod"
    case cafeyn
    case izneo = "cvs2"
    case numilog
    case toutApprendre = "tout-apprendre"
    case eureka = "bibliondemand"

    public var id: String { rawValue }

    /// Vrai quand l'URL du fournisseur rappelle le portail : il faut alors la session web
    /// (WKWebView avec le cookie), pas un simple Safari.
    public var needsPortalSession: Bool {
        switch self {
        case .cafeyn, .eureka: true
        case .arteVod, .izneo, .numilog, .toutApprendre: false
        }
    }
}

@DependencyClient
public struct DigitalClient: Sendable {
    /// URL SSO, à usage unique et de courte durée : à résoudre au moment du tap, jamais à l'avance.
    /// ⚠️ Elle peut contenir des données personnelles (Arte) : ne jamais la journaliser.
    public var target: @Sendable (_ service: DigitalService) async throws -> URL
    /// Cookies de la session web, à injecter dans un `WKWebView`.
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
