import Foundation

/// Transport vers le portail. Il porte la session web (cookie `PHPSESSID`),
/// qui suffit à l'API JSON `/api/user/*` comme aux pages du compte.
public actor HTTPClient {
    public static let villejuifBaseURL = URL(string: "https://mediatheque.villejuif.fr")!

    public nonisolated let baseURL: URL
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    public init(baseURL: URL = HTTPClient.villejuifBaseURL, userAgent: String = HTTPClient.defaultUserAgent) {
        self.baseURL = baseURL
        let cookieStorage = HTTPCookieStorage()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "fr-FR,fr;q=0.9",
        ]
        self.cookieStorage = cookieStorage
        self.session = URLSession(configuration: configuration)
    }

    public static let defaultUserAgent = "MediathequesVillejuif-iOS/1.0"

    // MARK: Requêtes

    public func data(for endpoint: Endpoint) async throws -> Data {
        let (data, response) = try await session.data(for: request(for: endpoint))
        guard let http = response as? HTTPURLResponse else {
            throw BokehError.unexpectedFormat("réponse non HTTP")
        }
        if http.url?.path.hasPrefix("/auth/login") == true, endpoint.pathSegments.first != "auth" {
            // Une page protégée nous a renvoyés vers la connexion.
            throw BokehError.unauthorized
        }
        guard (200..<400).contains(http.statusCode) else {
            throw BokehError.http(status: http.statusCode)
        }
        if http.mimeType == "application/json" || endpoint.isAjax, let error = BokehError.from(json: data) {
            throw error
        }
        return data
    }

    public func decode<T: Decodable & Sendable>(_ type: T.Type, from endpoint: Endpoint) async throws -> T {
        let data = try await data(for: endpoint)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BokehError.unexpectedFormat("\(T.self) : \(error)")
        }
    }

    public func string(for endpoint: Endpoint) async throws -> String {
        let data = try await data(for: endpoint)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Session

    /// Cookies de la session web, à injecter dans un `WKWebView` pour le SSO numérique.
    public func sessionCookies() -> [HTTPCookie] {
        cookieStorage.cookies(for: baseURL) ?? []
    }

    public var hasSessionCookie: Bool {
        sessionCookies().contains { $0.name == "PHPSESSID" }
    }

    public func clearSession() {
        cookieStorage.cookies?.forEach(cookieStorage.deleteCookie)
    }

    // MARK: Construction

    nonisolated func request(for endpoint: Endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint.url(relativeTo: baseURL))
        request.httpMethod = endpoint.method.rawValue
        if endpoint.isAjax {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        if endpoint.method == .post {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
            request.httpBody = Data(Self.formEncoded(endpoint.form).utf8)
        }
        return request
    }

    static func formEncoded(_ fields: [Endpoint.FormField]) -> String {
        fields
            .map { "\(formEscape($0.name))=\(formEscape($0.value))" }
            .joined(separator: "&")
    }

    private static func formEscape(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return (string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string)
            .replacingOccurrences(of: "%20", with: "+")
    }
}
