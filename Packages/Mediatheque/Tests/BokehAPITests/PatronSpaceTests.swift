// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
@testable import BokehAPI

struct PatronSpaceTests {
    let base = HTTPClient.villejuifBaseURL

    @Test func selectionsWithAndWithoutBasket() throws {
        let selections = try HTMLParsers.selections(in: Fixture.string("selections.html"))
        #expect(selections.map(\.title) == ["Mes préférés", "Déjà lu"])

        let favorites = try #require(selections.first)
        #expect(favorites.id == 9001)
        #expect(favorites.basketID == 501)
        #expect(favorites.count == 2)
        #expect(favorites.updatedText == "30/10/2026")
        #expect(favorites.coverURLs.count == 1)
        #expect(favorites.previewTitles == ["Astérix le Gaulois"])

        let read = selections[1]
        #expect(read.id == 9002)
        #expect(read.basketID == nil)
        #expect(read.count == 0)
    }

    @Test func recordsToRateCarryTheReviewForm() throws {
        let record = try #require(HTMLParsers.recordsToRate(in: Fixture.string("records-to-rate.html")).first)
        #expect(record.recordID == 123456)
        #expect(record.recordKey == "LEPETITPRINCE--SAINTEXUPERYA-")
        #expect(record.title == "Le Petit Prince")
        #expect(record.author == "Antoine de Saint-Exupéry")
        #expect(record.coverURL?.lastPathComponent == "123456.jpe")
    }

    @Test func emptyReviewsPage() throws {
        #expect(try HTMLParsers.reviews(in: Fixture.string("empty-reviews.html")).isEmpty)
    }

    @Test func contactFormValues() throws {
        let html = try Fixture.string("contact-form.html")
        #expect(try HTMLParsers.fieldValue("pseudo", in: html) == nil)
        #expect(try HTMLParsers.fieldValue("mail", in: html) == "camille.martin@exemple.fr")
        #expect(try HTMLParsers.checkedValue("favoriteSendingChannel", in: html) == "1")
    }

    @Test func bookmarkedLibrariesComeFromRemoveLinks() throws {
        #expect(try HTMLParsers.bookmarkedLibraryIDs(in: Fixture.string("selections.html")) == [3])
    }

    @Test func formErrorsAreRead() throws {
        let html = #"<div class="jumbotron_rich_content"><ul class="errors"><li>Les mots de passe ne correspondent pas</li></ul></div>"#
        #expect(try HTMLParsers.formErrors(in: html) == ["Les mots de passe ne correspondent pas"])
        #expect(try HTMLParsers.formErrors(in: Fixture.string("contact-form.html")).isEmpty)
    }

    @Test func patronSpaceRoutes() {
        #expect(Endpoint.patronPage("selections", patronID: "100001").url(relativeTo: base).path()
            == "/abonne/selections/id_profil/1/id/100001")
        #expect(Endpoint.selectionRecords(basketID: 501, page: 2).url(relativeTo: base).path()
            == "/recherche/simple/id_panier/501/format/json/page/2")
        #expect(Endpoint.removeFromSelection(patronID: "100001", selectionID: 9001, recordID: 123456).url(relativeTo: base).path()
            == "/abonne/supprimer-de-la-selection/id_profil/1/id/100001/selection_id/9001/record_id/123456/delete/1")

        let review = Endpoint.submitReview(recordID: 123456, recordKey: "LEPETITPRINCE--SAINTEXUPERYA-", rating: 4, title: "Beau", text: "")
        #expect(review.method == .post)
        #expect(review.form.map(\.name) == ["note", "entete", "avis"])
        #expect(review.form.first?.value == "4")
    }

    @Test func accountExposesPatronIDAndPreferences() throws {
        let account = try JSONDecoder().decode(AccountResponseDTO.self, from: Fixture.data("account.json")).account
        #expect(account.cards?.first?.id == 100001)
        #expect(account.identity.nickname == "")
        #expect(account.preferences?.newsletters.isEmpty == true)
    }
}
