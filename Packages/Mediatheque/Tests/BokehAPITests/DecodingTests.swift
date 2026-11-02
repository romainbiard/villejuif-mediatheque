// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
@testable import BokehAPI

struct DecodingTests {
    @Test func searchResponse() throws {
        let response = try JSONDecoder().decode(SearchResponseDTO.self, from: Fixture.data("search-harry-potter.json"))
        #expect(response.total == 2)
        let record = try #require(response.records.first)
        #expect(record.titles.contains("Harry Potter à l'école des sorciers"))
        #expect(record.creators == ["Rowling|Joanne Kathleen"])
        #expect(record.serial == "Harry Potter")
        #expect(record.type.code == "1")
        #expect(record.noticeID == 745828)
        let item = try #require(record.items.first)
        #expect(item.subfield("a") == "Médiathèque Elsa-Triolet")
        #expect(item.shelfMark == "SF ROW")
    }

    @Test func digitalRecordHasNoZone995() throws {
        let response = try JSONDecoder().decode(SearchResponseDTO.self, from: Fixture.data("search-artevod.json"))
        let record = try #require(response.records.first)
        #expect(record.type.code == "ArteVod")
        #expect(record.items.first?.zone995.isEmpty == true)
        #expect(record.items.first?.activity == "A consulter sur le portail")
    }

    @Test func account() throws {
        let account = try JSONDecoder().decode(AccountResponseDTO.self, from: Fixture.data("account.json")).account
        #expect(account.login == "0012345")
        #expect(account.libraryDetails.label == "PULP Nord")
        #expect(account.counters.lateLoans == 1)
        #expect(account.counters.waitingToBePulled == 1)
        #expect(account.card.expireAt == "2027-03-14")
        #expect(account.permissions.holdForbidden == false)
    }

    @Test func loansAndHolds() throws {
        let loans = try JSONDecoder().decode(LoansResponseDTO.self, from: Fixture.data("loans.json")).loans
        #expect(loans.count == 3)
        #expect(loans[0].id == "100001_36674")
        #expect(loans[0].dateDue == "2026-11-20")
        #expect(loans[1].record?.thumbnail == "")

        let holds = try JSONDecoder().decode(HoldsResponseDTO.self, from: Fixture.data("holds.json")).holds
        #expect(holds.first?.status == "Pas disponible avant le 14/11/2026")
        #expect(holds.first?.library == "PULP Nord")
    }

    @Test func holdConfirmationPopup() throws {
        let popup = try JSONDecoder().decode(PopupDTO.self, from: Fixture.data("hold-confirmation.json"))
        #expect(popup.title == "Réservation")
        #expect(popup.content.hasPrefix("Votre réservation est enregistrée."))
    }
}
