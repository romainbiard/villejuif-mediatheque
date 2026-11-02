// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import BokehAPI
@testable import MediathequeCore

/// Real calls to the portal, on public routes only.
/// Run with `LIVE_TESTS=1 swift test --filter LiveSmokeTests` to detect a format change.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1"),
    .dependency(\.context, .live)
)
struct LiveSmokeTests {
    @Test func searchAvailabilityAndCopies() async throws {
        let catalog = CatalogClient.liveValue
        let page = try await catalog.search(SearchQuery(text: "harry potter", kinds: [.book], libraries: [.elsaTriolet]))
        #expect(page.total > 0)
        let document = try #require(page.documents.first)
        _ = try await catalog.availability(document.id)
        let copies = try await catalog.copies(document.id)
        #expect(!copies.isEmpty)
    }

    @Test func agendaEvents() async throws {
        let events = try await AgendaClient.liveValue.events(.reload).value
        #expect(!events.isEmpty)
        #expect(events.contains { $0.start != nil })
        let detail = try await AgendaClient.liveValue.detail(try #require(events.first { !$0.isAllDay }))
        #expect(detail.descriptionText != nil)
    }

    /// Without a session cookie, sign-in cannot succeed (bug fixed in P3).
    @Test func sessionCookieIsKept() async throws {
        let http = HTTPClient()
        _ = try await http.string(for: .loginPage)
        #expect(await http.hasSessionCookie)
    }

    @Test func libraries() async throws {
        let libraries = try await LibraryClient.liveValue.libraries(.reload).value
        #expect(Set(libraries.compactMap(\.library)) == Set(Library.allCases))
        #expect(libraries.allSatisfy { !$0.hours.slotsByWeekday.isEmpty })
    }
}
