// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Foundation
import Synchronization

/// A fake portal for one test: the real `HTTPClient` and clients run, but each request is answered
/// by `respond` instead of the network. Each stub has its own host, so tests can run in parallel.
public final class PortalStub: Sendable {
    /// What the fake portal sends back.
    public struct Response: Sendable {
        public var status: Int
        public var body: Data
        public var contentType: String
        /// Final URL after a redirect (e.g. the sign-in page when the session has expired).
        public var redirectedPath: String?

        public init(status: Int = 200, body: Data, contentType: String, redirectedPath: String? = nil) {
            self.status = status
            self.body = body
            self.contentType = contentType
            self.redirectedPath = redirectedPath
        }

        public static func json(_ fixture: String) throws -> Response {
            try Response(body: Fixture.data(fixture), contentType: "application/json")
        }

        public static func json(literal: String) -> Response {
            Response(body: Data(literal.utf8), contentType: "application/json")
        }

        public static func html(_ fixture: String) throws -> Response {
            try Response(body: Fixture.data(fixture), contentType: "text/html")
        }

        public static func html(literal: String) -> Response {
            Response(body: Data(literal.utf8), contentType: "text/html")
        }

        public static func text(_ fixture: String) throws -> Response {
            try Response(body: Fixture.data(fixture), contentType: "text/calendar")
        }

        /// The JSON API's answer when the web session has expired.
        public static var expiredSession: Response {
            get throws { try json("api-error.json") }
        }
    }

    /// A request as the portal received it: method, path and form fields.
    public struct Request: Sendable {
        public let method: String
        public let path: String
        public let form: [String: String]
        /// The requests received before this one, oldest first: lets a page change after a sign-in.
        public let earlier: [Request]
    }

    public let baseURL: URL
    private let respond: @Sendable (Request) throws -> Response
    private let received = Mutex<[Request]>([])

    public init(respond: @escaping @Sendable (Request) throws -> Response) {
        baseURL = URL(string: "https://portal-\(UUID().uuidString.lowercased()).test")!
        self.respond = respond
        let host = baseURL.host()!
        Self.registry.withLock { $0[host] = self }
    }

    /// Requests received so far, in order.
    public var requests: [Request] { received.withLock { $0 } }

    /// How many requests went to this path.
    public func count(_ path: String) -> Int {
        requests.count { $0.path == path }
    }

    /// The real transport, wired to this fake portal.
    public func makeHTTPClient() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return HTTPClient(baseURL: baseURL, configuration: configuration)
    }

    // MARK: Routing

    fileprivate static let registry = Mutex<[String: PortalStub]>([:])

    fileprivate func answer(_ urlRequest: URLRequest) throws -> (HTTPURLResponse, Data) {
        let request = received.withLock { received in
            let request = Request(
                method: urlRequest.httpMethod ?? "GET",
                path: urlRequest.url?.path() ?? "",
                form: Self.form(from: urlRequest),
                earlier: received
            )
            received.append(request)
            return request
        }
        let response = try respond(request)
        var url = urlRequest.url ?? baseURL
        if let redirectedPath = response.redirectedPath { url = baseURL.appending(path: redirectedPath) }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": "\(response.contentType); charset=utf-8"
        ])!
        return (http, response.body)
    }

    private static func form(from request: URLRequest) -> [String: String] {
        let body = request.httpBody ?? request.httpBodyStream.map(readAll) ?? Data()
        let text = String(decoding: body, as: UTF8.self)
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Hands every request for a stub's host to that stub.
final class StubURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host() else { return false }
        return PortalStub.registry.withLock { $0[host] } != nil
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host(), let stub = PortalStub.registry.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (response, data) = try stub.answer(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
