// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import AgendaFeature
@testable import InfoFeature

@MainActor
struct AgendaViewModelTests {
    func makeViewModel(now: Date) async -> AgendaViewModel {
        let viewModel = withDependencies {
            $0.date.now = now
            $0.agendaClient.events = { _ in Cached(SampleData.events) }
        } operation: {
            AgendaViewModel()
        }
        await viewModel.load()
        return viewModel
    }

    @Test func voiceOverSaysWhatTheDayDotAndGreyMean() async {
        let viewModel = await makeViewModel(now: paris(2026, 11, 2, 0))
        // Monday 2: libraries closed. Wednesday 4: a sample event at 16:00. Friday 6: nothing.
        #expect(viewModel.accessibilityValue(for: paris(2026, 11, 2, 0)) == "Médiathèques fermées")
        #expect(viewModel.accessibilityValue(for: paris(2026, 11, 4, 0)) == "Des animations")
        #expect(viewModel.accessibilityValue(for: paris(2026, 11, 6, 0)).isEmpty)
    }

    @Test func eventsOfTheDayAndOngoing() async {
        // Saturday 31 October 2026.
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        #expect(viewModel.eventsOfSelectedDay.map(\.id) == [990])
        #expect(viewModel.ongoingEvents.map(\.id) == [983])
        #expect(viewModel.days.count == 14)
        #expect(viewModel.hasEvents(on: paris(2026, 11, 4, 0)))
    }

    @Test func emptyDaySuggestsNextDayWithEvents() async {
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        viewModel.select(day: paris(2026, 11, 2, 0))
        #expect(viewModel.eventsOfSelectedDay.isEmpty)
        #expect(viewModel.isLibraryClosingDay(viewModel.selectedDay))
        #expect(viewModel.nextDayWithEvents == paris(2026, 11, 4, 0))
        #expect(viewModel.feedback == .selection)
    }

    @Test func filtersAreAppliedLocally() async {
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        var filters = AgendaFilters()
        filters.types = ["Rencontre"]
        #expect(viewModel.upcomingCount(with: filters) == 1)
        viewModel.filters = filters
        #expect(viewModel.eventsOfSelectedDay.isEmpty)
        #expect(viewModel.availableTypes == ["Lectures", "Rencontre"])
        #expect(viewModel.availablePlaces.first == "Pulp Nord" || viewModel.availablePlaces.first == "Médiathèque Elsa-Triolet")
    }

    @Test func monthCalendarStartsOnMondayAndStaysInTheFuture() async {
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        // 1 October 2026 is a Thursday: 3 empty cells (Monday to Wednesday).
        #expect(viewModel.displayedMonth == paris(2026, 10, 1, 0))
        #expect(viewModel.monthGrid.prefix(3).allSatisfy { $0 == nil })
        #expect(viewModel.monthGrid.count == 3 + 31)
        #expect(!viewModel.canShowPreviousMonth)
        #expect(!viewModel.isSelectable(paris(2026, 10, 30, 0)))
        #expect(viewModel.isSelectable(paris(2026, 10, 31, 0)))

        viewModel.showNextMonth()
        // 1 November 2026 is a Sunday: 6 empty cells.
        #expect(viewModel.displayedMonth == paris(2026, 11, 1, 0))
        #expect(viewModel.monthGrid.prefix(6).allSatisfy { $0 == nil })
        #expect(viewModel.monthGrid[6] == paris(2026, 11, 1, 0))
        #expect(viewModel.canShowPreviousMonth)

        viewModel.showPreviousMonth()
        viewModel.select(day: paris(2026, 12, 2, 0))
        #expect(viewModel.displayedMonth == paris(2026, 12, 1, 0))
    }

    @Test func savedAgendaSaysItCouldNotUpdate() async {
        let viewModel = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_793_000_000)
            $0.agendaClient.events = { _ in Cached(SampleData.events, refreshError: .siteUnavailable) }
        } operation: { AgendaViewModel() }
        await viewModel.load()
        #expect(viewModel.state.value == SampleData.events)
        #expect(viewModel.staleError?.staleText == "Mise à jour impossible · dernières données enregistrées")
    }
}

@MainActor
struct InfoViewModelTests {
    func makeViewModel(now: Date) async -> InfoViewModel {
        let viewModel = withDependencies {
            $0.date.now = now
            $0.libraryClient.libraries = { _ in Cached(SampleData.libraries.reversed()) }
        } operation: {
            InfoViewModel()
        }
        await viewModel.load()
        return viewModel
    }

    @Test func librariesAreSortedAndStatusComputed() async throws {
        // Friday 30 October 2026 at 20:00, after closing time.
        let viewModel = await makeViewModel(now: paris(2026, 10, 30, 20))
        let libraries = try #require(viewModel.state.value)
        #expect(libraries.map(\.library) == [.elsaTriolet, .pulpSud, .pulpNord])
        #expect(viewModel.statusText(of: libraries[0]) == "Fermé · ouvre demain à 10:00")
        #expect(!viewModel.isOpen(libraries[0]))
    }

    @Test func openStatus() async throws {
        // Wednesday 4 November 2026 at 11:00.
        let viewModel = await makeViewModel(now: paris(2026, 11, 4, 11))
        let elsa = try #require(viewModel.state.value?.first)
        #expect(viewModel.statusText(of: elsa) == "Ouvert · ferme à 19:00")
        #expect(viewModel.isToday("Mercredi : 10h - 19h"))
    }
}

@MainActor
struct AgendaPeriodTests {
    /// Thursday 29 October 2026, during the All Saints' holidays.
    let thursday = paris(2026, 10, 29, 9)

    func makeViewModel(period: AgendaPeriod) async -> AgendaViewModel {
        let viewModel = withDependencies {
            $0.date.now = thursday
            $0.agendaClient.events = { _ in Cached(SampleData.events) }
        } operation: { AgendaViewModel() }
        await viewModel.load()
        viewModel.filters.period = period
        return viewModel
    }

    @Test func weekendDays() {
        #expect(AgendaPeriod.weekend.days(from: thursday, calendar: .paris) == [paris(2026, 10, 31, 0), paris(2026, 11, 1, 0)])
        #expect(AgendaPeriod.weekend.days(from: paris(2026, 10, 31, 15), calendar: .paris) == [paris(2026, 10, 31, 0), paris(2026, 11, 1, 0)])
        #expect(AgendaPeriod.weekend.days(from: paris(2026, 11, 1, 15), calendar: .paris) == [paris(2026, 11, 1, 0)])
        #expect(AgendaPeriod.all.days(from: thursday, calendar: .paris).isEmpty)
    }

    @Test func wednesdaysStartAtTheNextOne() {
        let days = AgendaPeriod.wednesdays.days(from: thursday, calendar: .paris)
        #expect(days.count == AgendaPeriod.wednesdayWeeks)
        #expect(days.first == paris(2026, 11, 4, 0))
        #expect(AgendaPeriod.wednesdays.days(from: paris(2026, 11, 4, 8), calendar: .paris).first == paris(2026, 11, 4, 0))
    }

    @Test func schoolHolidaysAreTheCurrentOrNextOnes() {
        let toussaint = AgendaPeriod.schoolHolidays.days(from: thursday, calendar: .paris)
        #expect(toussaint == [paris(2026, 10, 29, 0), paris(2026, 10, 30, 0), paris(2026, 10, 31, 0), paris(2026, 11, 1, 0)])

        let christmas = AgendaPeriod.schoolHolidays.days(from: paris(2026, 11, 3, 0), calendar: .paris)
        #expect(christmas.first == paris(2026, 12, 19, 0))
        #expect(christmas.last == paris(2027, 1, 3, 0))
    }

    @Test func weekendGroupsEventsByDay() async {
        let viewModel = await makeViewModel(period: .weekend)
        #expect(viewModel.periodDays.map(\.day) == [paris(2026, 10, 31, 0)])
        #expect(viewModel.periodDays.first?.events.map(\.id) == [990])
        #expect(viewModel.periodOngoingEvents.map(\.id) == [983])
        #expect(viewModel.filters.count == 1)
    }

    @Test func countIncludesThePeriod() async {
        let viewModel = await makeViewModel(period: .all)
        var filters = AgendaFilters()
        filters.period = .wednesdays
        // The talk on Wednesday the 4th and the prize, which spans every Wednesday.
        #expect(viewModel.upcomingCount(with: filters) == 2)
        filters.types = ["Lectures"]
        #expect(viewModel.upcomingCount(with: filters) == 0)
    }

    @Test func holidaySummaryNamesTheHolidays() async {
        let viewModel = await makeViewModel(period: .schoolHolidays)
        #expect(viewModel.periodSummary?.hasPrefix("Vacances de la Toussaint, du 17 octobre au ") == true)
        viewModel.clearPeriod()
        #expect(viewModel.filters.period == .all)
        #expect(viewModel.periodSummary == nil)
    }
}
