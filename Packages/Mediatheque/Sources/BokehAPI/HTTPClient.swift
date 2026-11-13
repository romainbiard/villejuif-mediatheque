// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Transport to the portal. It carries the web session (`PHPSESSID` cookie),
/// which is enough for the `/api/user/*` JSON API as well as the account pages.
public actor HTTPClient {
    public static let villejuifBaseURL = URL(string: "https://mediatheque.villejuif.fr")!

    public nonisolated let baseURL: URL
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let userAgent: String
    private let solveChallenge: ChallengeSolver
    /// Shared by the requests that hit the challenge at the same time, so it's solved only once.
    private var pendingChallenge: Task<Void, Error>?
    /// Bumped by each solved challenge: a request sent before the last solve only needs a replay.
    private var challengeGeneration = 0

    /// Solves the BunkerWeb challenge at the given URL and returns the cookies to keep.
    public typealias ChallengeSolver = @Sendable (
        _ url: URL, _ userAgent: String, _ cookies: [HTTPCookie]
    ) async throws -> [HTTPCookie]

    /// `configuration` is ephemeral by default (session cookie in memory only); tests pass one
    /// whose `protocolClasses` answer with captured pages instead of the network.
    public init(
        baseURL: URL = HTTPClient.villejuifBaseURL,
        userAgent: String = HTTPClient.defaultUserAgent,
        configuration: URLSessionConfiguration = .ephemeral,
        solveChallenge: @escaping ChallengeSolver = { url, userAgent, cookies in
            try await BunkerWebChallenge.solve(url: url, userAgent: userAgent, cookies: cookies)
        }
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.solveChallenge = solveChallenge
        // We keep the in-memory storage of the ephemeral configuration:
        // a hand-made `HTTPCookieStorage()` instance doesn't retain any cookie.
        let cookieStorage = configuration.httpCookieStorage ?? HTTPCookieStorage()
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "fr-FR,fr;q=0.9"
        ]
        self.cookieStorage = cookieStorage
        session = URLSession(configuration: configuration)
    }

    public static let defaultUserAgent = "MediathequesVillejuif-iOS/1.0"

    // MARK: Requests

    public func data(for endpoint: Endpoint) async throws -> Data {
        let generation = challengeGeneration
        var (data, http) = try await response(for: endpoint)
        if let challengeURL = Self.challengeURL(of: http) {
            // BunkerWeb wants to check we're a browser: solve it (unless another request
            // already did while this one was in flight), then replay the request once.
            if generation == challengeGeneration {
                try await passChallenge(at: challengeURL)
            }
            (data, http) = try await response(for: endpoint)
            if Self.challengeURL(of: http) != nil { throw BokehError.challengeFailed }
        }
        if http.url?.path.hasPrefix("/auth/login") == true, endpoint.pathSegments.first != "auth" {
            // A protected page redirected us to sign-in.
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

    private func response(for endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request(for: endpoint))
        guard let http = response as? HTTPURLResponse else {
            throw BokehError.unexpectedFormat("réponse non HTTP")
        }
        return (data, http)
    }

    // MARK: BunkerWeb challenge

    /// The challenge page the request was redirected to, if any.
    private static func challengeURL(of response: HTTPURLResponse) -> URL? {
        guard let url = response.url, url.path() == BunkerWebChallenge.path else { return nil }
        return url
    }

    private func passChallenge(at url: URL) async throws {
        if let pendingChallenge {
            return try await pendingChallenge.value
        }
        let task = Task { [cookieStorage, userAgent, solveChallenge, baseURL] in
            let cookies = try await solveChallenge(url, userAgent, cookieStorage.cookies(for: baseURL) ?? [])
            cookieStorage.setCookies(cookies, for: baseURL, mainDocumentURL: nil)
        }
        pendingChallenge = task
        defer { pendingChallenge = nil }
        try await task.value
        challengeGeneration += 1
    }

    // MARK: Session

    /// Web session cookies, to inject into a `WKWebView` for digital SSO.
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
