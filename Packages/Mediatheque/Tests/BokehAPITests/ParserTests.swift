// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
import TestSupport
@testable import BokehAPI

struct ParserTests {
    @Test func iCalEvent() throws {
        let event = try #require(ICalParser.events(from: Fixture.string("event-1019.ics")).first)
        #expect(event.uid == "1019")
        #expect(event.summary == "Conférence : IA - Comprendre les outils d’aujourd’hui")
        #expect(event.location == "Médiathèque Elsa-Triolet")
        #expect(event.latitude == 48.792636)
        #expect(event.longitude == 2.362783)
        #expect(event.imageURL?.absoluteString.hasSuffix("323onfrence-ia.jpg") == true)
        #expect(event.descriptionText?.contains("Nasreddine Menacer, professeur") == true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let start = try calendar.dateComponents([.year, .month, .day, .hour, .minute], from: #require(event.start))
        #expect(start == DateComponents(year: 2026, month: 11, day: 4, hour: 16, minute: 0))
    }

    @Test func explicitCredentialRefusal() throws {
        #expect(try HTMLParsers.loginRejected(in: Fixture.string("login-rejected.html")))
        // A blank sign-in form or any other page is not a refusal.
        #expect(try !HTMLParsers.loginRejected(in: Fixture.string("login.html")))
        #expect(try !HTMLParsers.loginRejected(in: "<html><body><p>Service indisponible</p></body></html>"))
        #expect(try !HTMLParsers
            .loginRejected(in: #"<ul class="errors element_error_messages"><li class="element_error_message">Une valeur est requise.</li></ul>"#))
    }

    @Test func iCalUnfoldsContinuationLines() {
        #expect(ICalParser.unfold("A:abc\n def\nB:x") == ["A:abcdef", "B:x"])
    }

    @Test func calendarEvents() throws {
        let events = try HTMLParsers.calendarEvents(in: Fixture.string("calendar.html"))
        #expect(events.count >= 10)
        let ronde = try #require(events.first { $0.articleID == 990 })
        #expect(ronde.title == "Ronde des histoires")
        #expect(ronde.location == "Pulp Nord")
        #expect(ronde.startText == "31/10/2026 à 10:30")
        #expect(ronde.endText == "31/10/2026 à 11:00")
        #expect(ronde.eventType == "Lectures")
        #expect(ronde.audience == "Dès 4 ans")
        #expect(ronde.imageURL?.absoluteString.hasSuffix("ronde-des-histoires.jpg") == true)
        #expect(Set(events.map(\.articleID)).count == events.count)
    }

    @Test func liveCopies() throws {
        let copies = try HTMLParsers.copies(in: Fixture.string("notice-exemplaires.html"))
        let copy = try #require(copies.first)
        #expect(copy.libraryName == "Médiathèque Elsa-Triolet")
        #expect(copy.availability == "En prêt")
        #expect(copy.section == "Jeunesse")
        #expect(copy.shelfMark == "SF ROW")
        #expect(copy.dueDateText == "17/11/2026")
        #expect(copy.holdsText == "Déjà 2 réservations")
    }

    @Test func availabilityBadge() throws {
        let badge = try HTMLParsers.availability(in: Fixture.string("availability.html"))
        #expect(badge.label == "En prêt")
        #expect(badge.isAvailable == false)
    }

    @Test func libraries() throws {
        let libraries = try HTMLParsers.libraries(in: Fixture.string("infos-pratiques.html"))
        #expect(libraries.map(\.slug).sorted() == ["elsa_triolet", "pulp_nord", "pulp_sud"])
        let elsa = try #require(libraries.first { $0.slug == "elsa_triolet" })
        #expect(elsa.name == "Médiathèque Elsa-Triolet")
        #expect(elsa.addressLines == ["1 esplanade Pierre-Yves-Cosnier", "94800 Villejuif"])
        #expect(elsa.phone == "01 86 93 33 00")
        #expect(elsa.openingHours.first == "Mardi : 13h - 19h")
        #expect(elsa.openingHours.count == 5)
        #expect(elsa.bookmarkLibraryID == 1)
        #expect(elsa.contactURL?.absoluteString == "https://demarches.villejuif.fr/villejuif-et-moi/contact-services/?service_id=7")
    }

    @Test func csrfToken() throws {
        let token = try HTMLParsers.csrfToken(in: Fixture.string("login.html"))
        #expect(token.count >= 32)
    }

    @Test func pickupOptions() throws {
        let html = """
        <form><label><input type="radio" name="code_annexe" value="1">Médiathèque Elsa-Triolet</label>\
        <label><input type="radio" name="code_annexe" value="3" checked>PULP Nord</label>\
        <label><input type="radio" name="code_annexe" value="2">PULP Sud</label></form>
        """
        let options = try HTMLParsers.pickupOptions(in: html)
        #expect(options.map(\.code) == ["1", "3", "2"])
        #expect(options.first { $0.isSelected }?.label == "PULP Nord")
    }

    @Test func ssoTarget() throws {
        let url = try #require(HTMLParsers.ssoTarget(in: Fixture.string("sso-tout-apprendre.html")))
        #expect(url.host() == "biblio.toutapprendre.com")
    }

    @Test func holdRank() throws {
        let html = "<div>État de la réservation: Pas disponible avant le 14/11/2026 Le prochain document disponible est pour vous. Rang 1</div>"
        #expect(try HTMLParsers.holdRanks(in: html) == [1])
    }
}
