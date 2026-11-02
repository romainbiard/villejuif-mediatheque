// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
@testable import BokehAPI

struct EndpointTests {
    let base = HTTPClient.villejuifBaseURL

    @Test func searchEncodesQueryAndSortWildcard() {
        let url = Endpoint.search("harry potter").url(relativeTo: base)
        #expect(url.absoluteString == "https://mediatheque.villejuif.fr/recherche/simple/expressionRecherche/harry%20potter/tri/%2A/format/json")
    }

    @Test func searchCombinesFacetsAndPage() {
        let url = Endpoint.search("dune", facets: ["T1", "Y2"], page: 3).url(relativeTo: base)
        #expect(url.path(percentEncoded: true) == "/recherche/simple/expressionRecherche/dune/tri/%2A/facettes/T1-Y2/format/json/page/3")
    }

    @Test func renewJoinsLoanIDsWithSemicolon() {
        let endpoint = Endpoint.renewLoans(patronID: "100001", loanIDs: ["100001_1", "100001_2"])
        #expect(endpoint.url(relativeTo: base).path(percentEncoded: false) == "/abonne/prolongerPret/id_profil/1/id/100001/id_pret/100001_1;100001_2")
    }

    @Test func calendarUsesServerRenderedAgendaPage() {
        let url = Endpoint.calendar(placeID: 3, audienceID: 12).url(relativeTo: base)
        #expect(url.path() == "/accueil/agenda/place/3/custom_field_3/12")
    }

    @Test func suggestUsesQueryString() {
        let url = Endpoint.suggest("asterix et").url(relativeTo: base)
        #expect(url.absoluteString == "https://mediatheque.villejuif.fr/recherche/suggestajax?startsWith=asterix%20et")
    }

    @Test func loginIsFormEncodedPost() throws {
        let request = HTTPClient(baseURL: base).request(for: .login(cardNumber: "0012345", password: "a b&c", csrfToken: "tok"))
        #expect(request.httpMethod == "POST")
        let body = try String(decoding: #require(request.httpBody), as: UTF8.self)
        #expect(body == "username=0012345&password=a+b%26c&login=Se+connecter&csrftoken=tok")
    }

    @Test func ajaxEndpointsSendRequestedWithHeader() {
        let request = HTTPClient(baseURL: base).request(for: .holdOptions(recordID: 909376))
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
    }

    @Test func unauthorizedMessageIsRecognised() throws {
        #expect(try BokehError.from(json: Fixture.data("api-error.json")) == .unauthorized)
    }
}
