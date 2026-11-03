// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import ConcurrencyExtras
import Dependencies
import Foundation
import TestSupport
@testable import MediathequeCore

/// The live clients, on a fake portal and an in-memory keychain: everything from the request
/// to the result runs for real, without network.
struct PortalHarness {
    let portal: PortalStub
    let http: HTTPClient
    let stored: LockIsolated<Credentials?>
    let keychain: KeychainClient
    let session: SessionManager

    static let credentials = Credentials(cardNumber: "0012345", password: "secret")

    init(signedIn: Bool = true, respond: @escaping @Sendable (PortalStub.Request) throws -> PortalStub.Response) {
        portal = PortalStub(respond: respond)
        http = portal.makeHTTPClient()
        let stored = LockIsolated<Credentials?>(signedIn ? Self.credentials : nil)
        self.stored = stored
        keychain = KeychainClient(
            load: { stored.value },
            save: { stored.setValue($0) },
            delete: { stored.setValue(nil) }
        )
        session = SessionManager(http: http, keychain: keychain)
    }

    /// Builds a live client with this harness as its dependencies.
    func live<Client>(_ make: () -> Client) -> Client {
        withDependencies {
            $0.httpClient = http
            $0.keychainClient = keychain
            $0.sessionManager = session
        } operation: {
            make()
        }
    }
}

/// The sign-in pages, shared by the tests that open a session.
enum SignIn {
    static let form = "/auth/login"
    static let account = "/api/user/account"

    /// Answers the sign-in form; `nil` when the request is something else.
    static func respond(to request: PortalStub.Request, rejected: Bool = false) throws -> PortalStub.Response? {
        guard request.path == form else { return nil }
        if request.method == "GET" { return try .html("login.html") }
        return rejected ? try .html("login-rejected.html") : .html(literal: "<html><body><h1>Mon compte</h1></body></html>")
    }
}

extension PortalStub.Request {
    var isSignIn: Bool { method == "POST" && path == SignIn.form }

    /// Whether the sign-in form was posted before this request: the session is open.
    var afterSignIn: Bool { earlier.contains(where: \.isSignIn) }
}

extension PortalStub {
    var signIns: Int { requests.count(where: \.isSignIn) }
}
