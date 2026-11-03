// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Foundation
import Testing
import TestSupport
@testable import MediathequeCore

/// Sign-in and automatic reconnection, against a fake portal.
struct SessionManagerTests {
    /// Loans answer only once the sign-in form has been posted.
    private static func expiringLoans(rejected: Bool = false) -> @Sendable (PortalStub.Request) throws -> PortalStub.Response {
        { request in
            if let page = try SignIn.respond(to: request, rejected: rejected) { return page }
            if request.path == SignIn.account { return try .json("account.json") }
            return try request.afterSignIn ? .json("loans.json") : .expiredSession
        }
    }

    @Test func signInOpensTheSessionAndKeepsTheCredentials() async throws {
        let harness = PortalHarness(signedIn: false) { request in
            try SignIn.respond(to: request) ?? .json("account.json")
        }
        let patron = try await harness.session.login(PortalHarness.credentials)

        #expect(patron.cardNumber == "0012345")
        #expect(harness.stored.value == PortalHarness.credentials)
        let form = try #require(harness.portal.requests.first { $0.isSignIn }).form
        #expect(form["username"] == "0012345")
        #expect(form["password"] == "secret")
        #expect(form["csrftoken"]?.isEmpty == false)
    }

    @Test func refusedPasswordIsNeverKept() async throws {
        let harness = PortalHarness(signedIn: false) { request in
            try SignIn.respond(to: request, rejected: true) ?? .json("account.json")
        }
        await #expect(throws: AuthError.invalidCredentials) {
            try await harness.session.login(PortalHarness.credentials)
        }
        #expect(harness.stored.value == nil)
    }

    @Test func expiredSessionSignsInAgainThenRetries() async throws {
        let harness = PortalHarness(respond: Self.expiringLoans())
        let loans = try await harness.session.perform {
            try await harness.http.decode(LoansResponseDTO.self, from: .loans).loans
        }
        #expect(loans.count == 3)
        #expect(harness.portal.signIns == 1)
        // The expired call, then the same call once signed in again.
        #expect(harness.portal.count("/api/user/loans") == 2)
    }

    @Test func screensExpiringTogetherShareOneSignIn() async throws {
        let harness = PortalHarness(respond: Self.expiringLoans())
        async let first = harness.session.perform { try await harness.http.decode(LoansResponseDTO.self, from: .loans) }
        async let second = harness.session.perform { try await harness.http.decode(LoansResponseDTO.self, from: .loans) }
        _ = try await (first, second)
        #expect(harness.portal.signIns == 1)
    }

    @Test func storedPasswordRefusedOnReopenIsForgotten() async throws {
        let harness = PortalHarness(respond: Self.expiringLoans(rejected: true))
        await #expect(throws: AuthError.invalidCredentials) {
            try await harness.session.perform { try await harness.http.data(for: .loans) }
        }
        // Background refreshes stop signing in with a password the site refuses.
        #expect(harness.stored.value == nil)
    }

    @Test func sessionThatDoesNotOpenKeepsThePassword() async throws {
        // The form goes through, but the API still says the session is closed: a passing failure.
        let harness = PortalHarness { request in
            try SignIn.respond(to: request) ?? .expiredSession
        }
        await #expect(throws: AuthError.sessionNotOpened) {
            try await harness.session.perform { try await harness.http.data(for: .loans) }
        }
        #expect(harness.stored.value == PortalHarness.credentials)
    }

    @Test func withoutStoredCredentialsNothingIsSent() async throws {
        let harness = PortalHarness(signedIn: false) { _ in try .expiredSession }
        #expect(try await harness.session.restore() == nil)
        await #expect(throws: AuthError.notLoggedIn) {
            try await harness.session.perform { try await harness.http.data(for: .loans) }
        }
        // Only the expired call: no sign-in attempt without a password.
        #expect(harness.portal.requests.map(\.path) == ["/api/user/loans"])
    }

    @Test func expiredPageRedirectToSignInCountsAsExpired() async throws {
        // A patron page that redirects to the sign-in form means the same as the API's error.
        let harness = PortalHarness { request in
            if let page = try SignIn.respond(to: request) { return page }
            if request.path == SignIn.account { return try .json("account.json") }
            return request.afterSignIn
                ? .html(literal: "<p>Rang 1</p>")
                : PortalStub.Response(body: Data(), contentType: "text/html", redirectedPath: "/auth/login")
        }
        let page = try await harness.session.perform {
            try await harness.http.string(for: .holdsPage(patronID: "100001"))
        }
        #expect(page.contains("Rang 1"))
        #expect(harness.portal.signIns == 1)
    }
}
