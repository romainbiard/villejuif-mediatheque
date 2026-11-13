// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
import TestSupport
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
        #expect(loans[1].record?.thumbnail?.isEmpty == true)

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

/// Bokeh sends `null` for fields it usually fills: a `null` must not fail the whole response,
/// and one malformed item must not hide the others. Fictional data.
struct LenientAccountDecodingTests {
    @Test func holdsWithNullFieldsAndAMalformedOne() throws {
        let json = Data(#"""
        {"holds":[
          {"id":"100001_1","title":null,"status":null,"library":null,"record":null},
          {"title":"Sans identifiant","status":"Pas disponible avant le 14/11/2026","library":"PULP Nord"},
          {"id":"100001_2","title":"Un titre","status":"Disponible","library":"Elsa-Triolet","record":{"id":"oops"}}
        ]}
        """#.utf8)
        let holds = try JSONDecoder().decode(HoldsResponseDTO.self, from: json).holds

        // The hold without an identifier can't be cancelled: it is the only one skipped.
        #expect(holds.map(\.id) == ["100001_1", "100001_2"])
        #expect(holds[0].status == nil)
        #expect(holds[0].title.isEmpty)
        #expect(holds[0].library.isEmpty)
        // A malformed record only loses the cover, not the hold.
        #expect(holds[1].record == nil)
    }

    @Test func loansWithNullFieldsAndAMalformedOne() throws {
        let json = Data(#"""
        {"loans":[
          {"id":"100001_1","title":"Un DVD","author":null,"date_due":"2026-11-20","library":null,"record":null},
          {"id":null,"title":"Sans identifiant","author":"Quelqu'un","date_due":"2026-11-20","library":"PULP Sud"},
          {"id":"100001_2","title":"Une revue","author":"","date_due":"2026-11-27","library":"PULP Sud"}
        ]}
        """#.utf8)
        let loans = try JSONDecoder().decode(LoansResponseDTO.self, from: json).loans

        #expect(loans.map(\.id) == ["100001_1", "100001_2"])
        #expect(loans[0].author.isEmpty)
        #expect(loans[0].library.isEmpty)
        #expect(loans[0].dateDue == "2026-11-20")
    }

    @Test func accountWithNullsAndNumbersAsStrings() throws {
        let json = Data(#"""
        {"account":{
          "login":"0012345",
          "identity":{"first_name":"Camille","last_name":null,"nickname":null},
          "contact":{"email":null,"phone":"","mobile":null,"address":null,"zip_code":94800,"city":null},
          "card":null,
          "library_details":{"id":"3","label":"PULP Nord"},
          "permissions":{"hold_forbidden":0,"digital_resources_forbidden":null},
          "counters":{"loans":"2","late_loans":null,"waiting_to_be_pulled":1},
          "message":null,
          "preferences":null,
          "cards":[{"id":100001},{"id":null}]
        }}
        """#.utf8)
        let account = try JSONDecoder().decode(AccountResponseDTO.self, from: json).account

        #expect(account.login == "0012345")
        #expect(account.identity.firstName == "Camille")
        #expect(account.identity.lastName.isEmpty)
        #expect(account.contact.email.isEmpty)
        #expect(account.contact.zipCode == "94800")
        #expect(account.card.expireAt.isEmpty)
        #expect(account.card.expired == false)
        #expect(account.libraryDetails.id == 3)
        #expect(account.permissions.holdForbidden == false)
        #expect(account.counters.loans == 2)
        #expect(account.counters.lateLoans == 0)
        #expect(account.counters.waitingToBePulled == 1)
        #expect(account.message.content.isEmpty)
        #expect(account.preferences == nil)
        #expect(account.cards?.map(\.id) == [100001])
    }

    /// Without the card number, nothing in the account can work: that one stays strict.
    @Test func accountWithoutCardNumberFails() {
        let json = Data(#"{"account":{"login":null,"identity":{"first_name":"Camille","last_name":"Martin"}}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AccountResponseDTO.self, from: json) }
    }
}
