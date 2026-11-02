// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing
@testable import BokehAPI
@testable import MediathequeCore

struct MapperTests {
    @Test func creatorNamesAreReordered() {
        #expect(Notice.displayName(fromCreator: "Rowling|Joanne Kathleen") == "Joanne Kathleen Rowling")
        #expect(Notice.displayName(fromCreator: "Toto La Momposina") == "Toto La Momposina")
    }

    @Test func publisherPlaceIsStripped() {
        #expect(Notice.stripPlace("Gallimard jeunesse (Paris Cedex 07)") == "Gallimard jeunesse")
    }

    @Test func documentFromRecord() throws {
        let json = #"""
        {"identifier":"SWAY--TOTOG--IDOL-2018-3","titles":["Sway"],"serial":null,"creators":["Toto|Gérald"],"date":"2018",
         "publishers":["Idol"],"type":{"code":"3","label":"CD"},"thumbnail":"","permalink":"https://mediatheque.villejuif.fr/recherche/viewnotice/clef/SWAY--TOTOG--IDOL-2018-3/id/474169",
         "collections":[],"items":[{"id":1,"id_notice":474169,"annexe":"1","cote":"781.3 TOT","activite":"En rayon","id_bib":1,
         "zone995":[{"code":"a","valeur":"Médiathèque Elsa-Triolet"}]}]}
        """#
        let dto = try JSONDecoder().decode(RecordDTO.self, from: Data(json.utf8))
        let document = try #require(Notice(dto: dto))
        #expect(document.id == 474169)
        #expect(document.authors == ["Gérald Toto"])
        #expect(document.coverURL == nil)
        #expect(document.kind.isDigital == false)
        #expect(document.libraries == [.elsaTriolet])
    }

    @Test func liveCopyStatus() {
        let copy = LiveCopy(dto: CopyDTO(
            libraryName: "Médiathèque Elsa-Triolet", availability: "En prêt", section: "Jeunesse",
            shelfMark: "SF ROW", dueDateText: "17/11/2026", holdsText: "Déjà 2 réservations"
        ))
        #expect(copy.library == .elsaTriolet)
        #expect(copy.holdCount == 2)
        guard case let .onLoan(due) = copy.status else { Issue.record("statut inattendu"); return }
        #expect(due == SampleData.day(2026, 11, 17))
        #expect(LiveCopy.holdCount(from: "Déjà une réservation") == 1)
        let soon = LiveCopy(dto: CopyDTO(
            libraryName: "PULP Nord", availability: "Bientôt disponible", section: nil,
            shelfMark: nil, dueDateText: nil, holdsText: nil
        ))
        #expect(soon.status.isAvailable == false)
    }

    @Test func holdTitleAndExpectedDate() {
        #expect(Hold.cleanTitle("Astérix n° 39Astérix et le griffon") == "Astérix n° 39 · Astérix et le griffon")
        let hold = SampleData.holds[1]
        #expect(hold.expectedDate == SampleData.day(2026, 11, 14))
        #expect(hold.isReadyForPickup == false)
        #expect(SampleData.holds[0].isReadyForPickup == true)
    }

    @Test func calendarEventWithAndWithoutTime() {
        let timed = Event(dto: CalendarEventDTO(
            articleID: 990, title: "Ronde des histoires", imageURL: nil, location: "Pulp Nord",
            startText: "31/10/2026 à 10:30", endText: "31/10/2026 à 11:00", eventType: "Lectures", audience: "Dès 4 ans", dateSentence: nil
        ))
        #expect(timed.library == .pulpNord)
        #expect(timed.isAllDay == false)
        #expect(timed.start == SampleData.day(2026, 10, 31, 10, 30))

        let allDay = Event(dto: CalendarEventDTO(
            articleID: 983, title: "Prix", imageURL: nil, location: nil,
            startText: "26/09/2026", endText: "27/03/2027", eventType: nil, audience: nil, dateSentence: nil
        ))
        #expect(allDay.isAllDay)
        #expect(allDay.occurs(on: SampleData.day(2026, 12, 1, 12), calendar: BokehDates.parisCalendar))
    }

    @Test func libraryLabels() {
        #expect(Library(label: "Pulp Nord") == .pulpNord)
        #expect(Library(label: "PULP Sud") == .pulpSud)
        #expect(Library(label: "Médiathèque Elsa-Triolet") == .elsaTriolet)
        #expect(Library(label: "Théâtre Romain Rolland") == nil)
    }
}

struct OpeningHoursTests {
    let calendar = BokehDates.parisCalendar
    let elsa = OpeningHours(lines: ["Mardi : 13h - 19h", "Mercredi : 10h - 19h", "Samedi : 10h - 12h30 / 14h - 18h"])

    @Test func openDuringSlot() {
        // Wednesday 4 November 2026, 11:00.
        let status = elsa.status(at: SampleData.day(2026, 11, 4, 11), calendar: calendar)
        #expect(status == .open(closesAt: SampleData.day(2026, 11, 4, 19)))
    }

    @Test func closedBeforeOpeningSameDay() {
        let status = elsa.status(at: SampleData.day(2026, 11, 3, 9), calendar: calendar)
        #expect(status == .closed(reopensAt: SampleData.day(2026, 11, 3, 13)))
    }

    @Test func closedOverWeekendReopensTuesday() {
        // Sunday 1 November 2026.
        let status = elsa.status(at: SampleData.day(2026, 11, 1, 15), calendar: calendar)
        #expect(status == .closed(reopensAt: SampleData.day(2026, 11, 3, 13)))
        #expect(elsa.isClosedAllDay(SampleData.day(2026, 11, 2), calendar: calendar))
    }

    @Test func lunchBreakIsHandled() {
        // Saturday 31 October 2026, 13:00: between the two time slots.
        let status = elsa.status(at: SampleData.day(2026, 10, 31, 13), calendar: calendar)
        #expect(status == .closed(reopensAt: SampleData.day(2026, 10, 31, 14)))
    }
}

struct LoanTests {
    let calendar = BokehDates.parisCalendar
    let now = SampleData.day(2026, 10, 30, 21)

    @Test func dueStates() {
        #expect(SampleData.loans[0].dueState(now: now, calendar: calendar) == .late(days: 2))
        #expect(SampleData.loans[1].dueState(now: now, calendar: calendar) == .dueSoon(days: 6))
        #expect(SampleData.loans[2].dueState(now: now, calendar: calendar) == .onTime(days: 20))
    }

    @Test func patronIDComesFromLoanID() {
        #expect(SampleData.loans[0].patronID == "100001")
    }
}

struct ReturnsSummaryTests {
    private func paris(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        Calendar.paris.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func lateLoanComesFirstThenNextReturn() {
        let snapshot = AccountSnapshot(loans: SampleData.loans, holds: [], updatedAt: paris(10, 31))
        #expect(ReturnsSummary.sentence(for: snapshot, now: paris(10, 31), calendar: .paris)
            == "« Le Petit Prince » est en retard. Prochain retour : « Sway », dans 5 jours, le jeudi 5 novembre.")
    }

    @Test func nextReturnAndRemainingCount() {
        let snapshot = AccountSnapshot(loans: Array(SampleData.loans.dropFirst()), holds: [], updatedAt: paris(11, 1))
        #expect(ReturnsSummary.sentence(for: snapshot, now: paris(11, 1), calendar: .paris)
            == "Vous devez rendre « Sway » dans 4 jours, le jeudi 5 novembre. Puis 1 autre plus tard.")
        #expect(ReturnsSummary.sentence(for: snapshot, now: paris(11, 5), calendar: .paris)
            == "Vous devez rendre « Sway » aujourd'hui. Puis 1 autre plus tard.")
    }

    @Test func noSnapshotOrNoLoans() {
        #expect(ReturnsSummary.sentence(for: nil, now: paris(10, 31), calendar: .paris)
            == "Connectez-vous dans l'app Médiathèque pour suivre vos prêts.")
        let empty = AccountSnapshot(loans: [], holds: [], updatedAt: paris(10, 31))
        #expect(ReturnsSummary.sentence(for: empty, now: paris(10, 31), calendar: .paris) == "Vous n'avez aucun prêt en cours.")
    }
}

struct Code39Tests {
    @Test func everyCharacterHasThreeWideElementsOutOfNine() {
        for (character, pattern) in Code39.patterns {
            #expect(pattern.count == 9, "\(character)")
            #expect(pattern.count(where: { $0 == "w" }) == 3, "\(character)")
        }
    }

    @Test func digitsAreFramedByStartAndStop() throws {
        let elements = try #require(Code39.elements(for: "1234567"))
        // 9 characters (start, 7 digits, stop) of 9 elements each, and 8 spaces between them.
        #expect(elements.count == 9 * 9 + 8)
        #expect(elements.first?.isBar == true)
        #expect(elements.last?.isBar == true)
        let star = try #require(Code39.patterns["*"]?.map { $0 == "w" })
        #expect(elements.prefix(9).map(\.isWide) == star)
        #expect(elements.suffix(9).map(\.isWide) == star)
        // Digit "1" right after the start and its space: w n n w n n n n w.
        #expect(elements[10..<19].map(\.isWide) == [true, false, false, true, false, false, false, false, true])
        #expect(Code39.width(of: elements, wideRatio: 3) == Double(9 * 15 + 8))
    }

    @Test func unsupportedCharactersAreRejected() {
        #expect(Code39.elements(for: "é") == nil)
        #expect(Code39.elements(for: "12*3") == nil)
        #expect(Code39.elements(for: "ab-1") != nil)
    }
}

struct LoadErrorTextTests {
    @Test func eachErrorSaysWhatToDo() {
        let offline = LoadError(URLError(.notConnectedToInternet))
        #expect(offline.title == "Pas de connexion")
        #expect(offline.message == "Vérifiez votre connexion, puis réessayez.")
        #expect(offline.systemImage == "wifi.slash")

        let siteDown = LoadError(URLError(.timedOut))
        #expect(siteDown.title == "Le site de la médiathèque ne répond pas")
        #expect(siteDown.message == "Réessayez dans un instant.")
        #expect(siteDown.staleText == "Mise à jour impossible · dernières données enregistrées")
    }
}

struct DataCacheTests {
    private struct Failure: Error {}

    private func makeCache() -> (DataCache, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DataCacheTests-\(UUID().uuidString)")
        return (DataCache(directory: directory), directory)
    }

    @Test func freshValueAvoidsTheLoad() async throws {
        let (cache, _) = makeCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let first = try await cache.value(for: "k", maxAge: 60, now: { start }) { 1 }
        let second = try await cache.value(for: "k", maxAge: 60, now: { start + 30 }) { 2 }
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test func staleValueIsReloadedAndReloadPolicyBypassesTheCache() async throws {
        let (cache, _) = makeCache()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = try await cache.value(for: "k", maxAge: 60, now: { start }) { 1 }
        let stale = try await cache.value(for: "k", maxAge: 60, now: { start + 61 }) { 2 }
        let forced = try await cache.value(for: "k", maxAge: 60, policy: .reload, now: { start + 62 }) { 3 }
        #expect(stale == 2)
        #expect(forced == 3)
    }

    @Test func failedLoadFallsBackToTheStaleValue() async throws {
        let (cache, _) = makeCache()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = try await cache.value(for: "k", maxAge: 60, now: { start }) { "hier" }
        let offline: String = try await cache.value(for: "k", maxAge: 60, policy: .reload, now: { start + 3600 }) {
            throw Failure()
        }
        #expect(offline == "hier")
        await #expect(throws: Failure.self) {
            let _: String = try await cache.value(for: "absent", maxAge: 60) { throw Failure() }
        }
    }

    @Test func fallbackSaysTheRefreshFailed() async throws {
        let (cache, _) = makeCache()
        let start = Date(timeIntervalSince1970: 1_000)
        let fresh = try await cache.cached(for: "k", maxAge: 60, now: { start }) { "hier" }
        let offline: Cached<String> = try await cache.cached(for: "k", maxAge: 60, policy: .reload, now: { start + 3600 }) {
            throw URLError(.notConnectedToInternet)
        }
        #expect(fresh.refreshError == nil)
        #expect(offline.value == "hier")
        #expect(offline.refreshError == .offline)
    }

    @Test func valuesSurviveOnDiskButNotWhenMemoryOnly() async throws {
        let (cache, directory) = makeCache()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = try await cache.value(for: "disque", maxAge: 60, now: { start }) { [1, 2] }
        _ = try await cache.value(for: "mémoire", maxAge: 60, persist: false, now: { start }) { [3] }

        // New cache on the same folder: like when the app relaunches.
        let reopened = DataCache(directory: directory)
        let fromDisk: [Int] = try await reopened.value(for: "disque", maxAge: 60, now: { start + 10 }) { [] }
        let notPersisted: [Int] = try await reopened.value(for: "mémoire", maxAge: 60, persist: false, now: { start + 10 }) { [] }
        #expect(fromDisk == [1, 2])
        #expect(notPersisted == [])
    }
}
