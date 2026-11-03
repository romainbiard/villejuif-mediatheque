// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Foundation
import Testing
import TestSupport
@testable import MediathequeCore

/// The live clients against a fake portal serving captured pages: request, parsing and mapping run for real.
struct AccountClientLiveTests {
    @Test func loansComeFromTheAPI() async throws {
        let harness = PortalHarness { _ in try .json("loans.json") }
        let loans = try await harness.live { AccountClient.liveValue }.loans()
        #expect(loans.map(\.id) == ["100001_36674", "100001_55179", "100001_55180"])
    }

    @Test func holdsTakeTheirQueuePositionFromTheHoldsPage() async throws {
        let harness = PortalHarness { request in
            request.path.hasPrefix("/abonne/reservations/")
                ? .html(literal: "<html><body><p>Rang 2</p></body></html>")
                : try .json("holds.json")
        }
        let holds = try await harness.live { AccountClient.liveValue }.holds()
        #expect(holds.count == 1)
        #expect(holds.first?.rank == 2)
        // The HTML page uses the patron identifier taken from the hold's own identifier.
        #expect(harness.portal.requests.contains { $0.path == "/abonne/reservations/id_profil/1/id/100001" })
    }

    @Test func holdsStillShowWhenTheRankCantBeRead() async throws {
        let harness = PortalHarness { request in
            request.path.hasPrefix("/abonne/reservations/") ? PortalStub.Response(status: 500, body: Data(), contentType: "text/html") : try .json("holds.json")
        }
        let holds = try await harness.live { AccountClient.liveValue }.holds()
        #expect(holds.count == 1)
        #expect(holds.first?.rank == nil)
    }

    @Test func renewalComparesTheDueDatesBeforeAndAfter() async throws {
        // After the renewal, only the first loan has a later due date.
        let renewed = try Fixture.string("loans.json").replacingOccurrences(of: "2026-11-20", with: "2026-12-11")
        let harness = PortalHarness { request in
            if request.path.hasPrefix("/abonne/prolongerPret/") { return .html(literal: "<html></html>") }
            let afterRenewal = request.earlier.contains { $0.path.hasPrefix("/abonne/prolongerPret/") }
            return afterRenewal ? .json(literal: renewed) : try .json("loans.json")
        }
        let results = try await harness.live { AccountClient.liveValue }.renew(["100001_36674", "100001_55179"])

        #expect(results.count == 2)
        guard case let .renewed(id, newDueDate) = results[0] else { Issue.record("first loan not renewed"); return }
        #expect(id == "100001_36674")
        #expect(Calendar.paris.dateComponents([.month, .day], from: newDueDate) == DateComponents(month: 12, day: 11))
        #expect(results[1] == .refused(loanID: "100001_55179"))
        let renewal = try #require(harness.portal.requests.first { $0.path.hasPrefix("/abonne/prolongerPret/") })
        #expect(renewal.path.hasSuffix("100001_36674;100001_55179") || renewal.path.hasSuffix("100001_36674%3B100001_55179"))
    }

    @Test func preparingAHoldReadsTheLinkAndThePickupLibraries() async throws {
        let options = #"{"result":"CONTENT","content":"<a href=\"/recherche/reservation-pickup-ajax/record_id/7/copy_id/9/on_record/1\">Réserver</a>"}"#
        let form = #"{"result":"CONTENT","content":""#
            + #"<input type=\"radio\" name=\"code_annexe\" id=\"a1\" value=\"1\"><label for=\"a1\">Elsa-Triolet</label>"#
            + #"<input type=\"radio\" name=\"code_annexe\" id=\"a3\" value=\"3\" checked><label for=\"a3\">PULP Nord</label>"}"#
        let harness = PortalHarness { request in
            request.path.hasPrefix("/recherche/reserver/") ? .json(literal: options) : .json(literal: form)
        }
        let request = try await harness.live { AccountClient.liveValue }.prepareHold(7)
        #expect(request.pickupPath == "recherche/reservation-pickup-ajax/record_id/7/copy_id/9/on_record/1")
        #expect(request.pickupLibraries == [.elsaTriolet, .pulpNord])
        #expect(request.defaultPickup == .pulpNord)
    }

    @Test func placingAHoldReturnsTheSitesMessageWithoutHTML() async throws {
        let harness = PortalHarness { _ in try .json("hold-confirmation.json") }
        let request = HoldRequest(pickupPath: "recherche/reservation-pickup-ajax/record_id/7", pickupLibraries: [.pulpNord], defaultPickup: .pulpNord)
        let message = try await harness.live { AccountClient.liveValue }.placeHold(request, .pulpNord)

        #expect(message.hasPrefix("Votre réservation est enregistrée.\nNous vous informerons"))
        #expect(!message.contains("<"))
        #expect(harness.portal.requests.last?.form["code_annexe"] == Library.pulpNord.code)
    }

    @Test func aRefusedHoldSaysWhy() async throws {
        let harness = PortalHarness { _ in .json(literal: #"{"result":"CONTENT","content":"Vous avez atteint le nombre maximum de réservations."}"#) }
        let request = HoldRequest(pickupPath: "recherche/reservation-pickup-ajax/record_id/7", pickupLibraries: [.pulpNord], defaultPickup: .pulpNord)
        await #expect(throws: HoldError.refused(message: "Vous avez atteint le nombre maximum de réservations.")) {
            try await harness.live { AccountClient.liveValue }.placeHold(request, .pulpNord)
        }
    }

    @Test func cancellingAHoldCallsItsDeleteLink() async throws {
        let harness = PortalHarness { _ in .html(literal: "<html></html>") }
        try await harness.live { AccountClient.liveValue }.cancelHold("100001_101613")
        #expect(harness.portal.requests.map(\.path) == ["/abonne/reservations/id_delete/100001_101613"])
    }
}

struct CatalogAndAgendaLiveTests {
    @Test func searchDecodesTheResultsPage() async throws {
        let harness = PortalHarness { _ in try .json("search-harry-potter.json") }
        let page = try await harness.live { CatalogClient.liveValue }.search(SearchQuery(text: "harry potter live test"))
        #expect(page.total > 0)
        #expect(!page.documents.isEmpty)
        #expect(harness.portal.requests.first?.path.hasPrefix("/recherche/simple/expressionRecherche/") == true)
    }

    @Test func copiesComeFromTheLiveCopiesPage() async throws {
        let harness = PortalHarness { _ in try .html("notice-exemplaires.html") }
        let copies = try await harness.live { CatalogClient.liveValue }.copies(745828)
        #expect(!copies.isEmpty)
        #expect(harness.portal.requests.map(\.path) == ["/noticeajax/exemplaires/id/745828"])
    }

    @Test func availabilityBadgeIsRead() async throws {
        let harness = PortalHarness { _ in try .html("availability.html") }
        let availability = try await harness.live { CatalogClient.liveValue }.availability(990_001)
        #expect(!availability.label.isEmpty)
    }

    @Test func agendaReadsTheCalendarPageSortedByDate() async throws {
        let harness = PortalHarness { _ in try .html("calendar.html") }
        let events = try await harness.live { AgendaClient.liveValue }.events(.reload).value
        #expect(!events.isEmpty)
        let starts = events.compactMap(\.start)
        #expect(starts == starts.sorted())
    }

    @Test func eventDetailComesFromItsICal() async throws {
        let harness = PortalHarness { _ in try .text("event-1019.ics") }
        let event = try #require(SampleData.events.first)
        let detail = try await harness.live { AgendaClient.liveValue }.detail(event)
        #expect(detail.descriptionText?.isEmpty == false)
        #expect(detail.latitude != nil)
        #expect(harness.portal.requests.map(\.path) == ["/cms/ical/id_article/\(event.id)"])
    }

    @Test func digitalServiceResolvesItsSignInLink() async throws {
        let harness = PortalHarness { _ in try .html("sso-tout-apprendre.html") }
        let url = try await harness.live { DigitalClient.liveValue }.target(.toutApprendre)
        #expect(url.host() == "biblio.toutapprendre.com")
        #expect(harness.portal.requests.map(\.path) == ["/modules/tout-apprendre"])
    }
}

struct ProfileClientLiveTests {
    /// Patron pages: the account gives the patron identifier used in their path.
    private static func pages(_ pages: [String: PortalStub.Response]) -> @Sendable (PortalStub.Request) throws -> PortalStub.Response {
        { request in
            if request.path == SignIn.account { return try .json("account.json") }
            for (page, response) in pages where request.path == "/abonne/\(page)/id_profil/1/id/100001" {
                return response
            }
            return PortalStub.Response(status: 404, body: Data(), contentType: "text/html")
        }
    }

    @Test func selectionsAreReadFromThePatronsPage() async throws {
        let harness = try PortalHarness(respond: Self.pages(["selections": .html("selections.html")]))
        let selections = try await harness.live { ProfileClient.liveValue }.selections()
        #expect(!selections.isEmpty)
    }

    @Test func recordsToRateAndReviewsAreRead() async throws {
        let harness = try PortalHarness(respond: Self.pages([
            "donner-des-avis": .html("records-to-rate.html"),
            "mes-avis": .html("empty-reviews.html")
        ]))
        let client = harness.live { ProfileClient.liveValue }
        #expect(try await !client.recordsToRate().isEmpty)
        #expect(try await client.reviews().isEmpty)
    }

    @Test func passwordChangeSendsBothFieldsAndSurfacesTheSitesError() async throws {
        let rejection = #"<div class="jumbotron_rich_content"><ul class="errors"><li>Le mot de passe est trop court</li></ul></div>"#
        let harness = PortalHarness(respond: Self.pages(["changer-mon-mot-de-passe": .html(literal: rejection)]))
        await #expect(throws: ProfileError.rejected("Le mot de passe est trop court")) {
            try await harness.live { ProfileClient.liveValue }.changePassword("abc")
        }
        let form = try #require(harness.portal.requests.first { $0.method == "POST" }).form
        #expect(form["new_password"] == "abc")
        #expect(form["confirm_new_password"] == "abc")
    }

    @Test func contactDetailsAreReadFromTheForm() async throws {
        let harness = try PortalHarness(respond: Self.pages(["modifier": .html("contact-form.html")]))
        let details = try await harness.live { ProfileClient.liveValue }.contactDetails()
        #expect(!details.email.isEmpty)
    }

    @Test func defaultSelectionsAreReadFromTheRecordPage() async throws {
        let harness = PortalHarness { _ in try .html("notice-selections.html") }
        let selections = try await harness.live { ProfileClient.liveValue }.defaultSelections(720_102)
        #expect(selections == [.favorites])
        #expect(harness.portal.requests.map(\.path) == ["/recherche/viewnotice/id/720102"])
    }

    @Test func aPublicRecordPageMeansTheSessionExpired() async throws {
        // Signed out, the page shows every selection as "add": the client signs in again instead of emptying the heart.
        let harness = PortalHarness { request in
            if let page = try SignIn.respond(to: request) { return page }
            if request.path == SignIn.account { return try .json("account.json") }
            return try request
                .afterSignIn ? .html("notice-selections.html") : .html(literal: "<html><body><a href=\"/auth/login\">Mon compte</a></body></html>")
        }
        let selections = try await harness.live { ProfileClient.liveValue }.defaultSelections(720_102)
        #expect(selections == [.favorites])
        #expect(harness.portal.signIns == 1)
    }

    @Test func addingToASelectionChecksTheSitesAnswer() async throws {
        let harness = PortalHarness { _ in try .json("selection-added.json") }
        try await harness.live { ProfileClient.liveValue }.setInDefaultSelection(.favorites, 720_102, true)
        let request = try #require(harness.portal.requests.first)
        #expect(request.path.hasPrefix("/abonne/ajouter-le-document-a-la-selection/selection_label/"))
        #expect(request.path.hasSuffix("/record_id/720102"))
    }

    @Test func aToggleTheSiteDidNotApplyIsAnError() async throws {
        // Asked to add, but the site still offers "add": nothing changed.
        let harness = PortalHarness { _ in try .json("selection-removed.json") }
        await #expect(throws: ProfileError.selectionNotChanged) {
            try await harness.live { ProfileClient.liveValue }.setInDefaultSelection(.favorites, 720_102, true)
        }
    }
}
