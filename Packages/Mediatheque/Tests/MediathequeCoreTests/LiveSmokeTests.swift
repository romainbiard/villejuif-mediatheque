import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import BokehAPI
@testable import MediathequeCore

/// Appels réels au portail, sur les routes publiques uniquement.
/// Lancer avec `LIVE_TESTS=1 swift test --filter LiveSmokeTests` pour détecter un changement de format.
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
        let events = try await AgendaClient.liveValue.events()
        #expect(!events.isEmpty)
        #expect(events.contains { $0.start != nil })
        let detail = try await AgendaClient.liveValue.detail(try #require(events.first { !$0.isAllDay }))
        #expect(detail.descriptionText != nil)
    }

    /// Sans cookie de session, la connexion ne peut pas aboutir (bug corrigé en P3).
    @Test func sessionCookieIsKept() async throws {
        let http = HTTPClient()
        _ = try await http.string(for: .loginPage)
        #expect(await http.hasSessionCookie)
    }

    @Test func libraries() async throws {
        let libraries = try await LibraryClient.liveValue.libraries()
        #expect(Set(libraries.compactMap(\.library)) == Set(Library.allCases))
        #expect(libraries.allSatisfy { !$0.hours.slotsByWeekday.isEmpty })
    }
}
