import Dependencies
import DependenciesTestSupport
import Foundation
import MediathequeCore
import Testing
@testable import AgendaFeature
@testable import InfoFeature

private func paris(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@MainActor
struct AgendaViewModelTests {
    func makeViewModel(now: Date) async -> AgendaViewModel {
        let viewModel = withDependencies {
            $0.date.now = now
            $0.agendaClient.events = { SampleData.events }
        } operation: {
            AgendaViewModel()
        }
        await viewModel.load()
        return viewModel
    }

    @Test func eventsOfTheDayAndOngoing() async {
        // Samedi 31 octobre 2026.
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        #expect(viewModel.eventsOfSelectedDay.map(\.id) == [990])
        #expect(viewModel.ongoingEvents.map(\.id) == [983])
        #expect(viewModel.days.count == 14)
        #expect(viewModel.hasEvents(on: paris(2026, 11, 4)))
    }

    @Test func emptyDaySuggestsNextDayWithEvents() async {
        let viewModel = await makeViewModel(now: paris(2026, 10, 31, 9))
        viewModel.select(day: paris(2026, 11, 2))
        #expect(viewModel.eventsOfSelectedDay.isEmpty)
        #expect(viewModel.isLibraryClosingDay(viewModel.selectedDay))
        #expect(viewModel.nextDayWithEvents == paris(2026, 11, 4))
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
        // Le 1er octobre 2026 est un jeudi : 3 cases vides (lundi à mercredi).
        #expect(viewModel.displayedMonth == paris(2026, 10, 1))
        #expect(viewModel.monthGrid.prefix(3).allSatisfy { $0 == nil })
        #expect(viewModel.monthGrid.count == 3 + 31)
        #expect(!viewModel.canShowPreviousMonth)
        #expect(!viewModel.isSelectable(paris(2026, 10, 30)))
        #expect(viewModel.isSelectable(paris(2026, 10, 31)))

        viewModel.showNextMonth()
        // Le 1er novembre 2026 est un dimanche : 6 cases vides.
        #expect(viewModel.displayedMonth == paris(2026, 11, 1))
        #expect(viewModel.monthGrid.prefix(6).allSatisfy { $0 == nil })
        #expect(viewModel.monthGrid[6] == paris(2026, 11, 1))
        #expect(viewModel.canShowPreviousMonth)

        viewModel.showPreviousMonth()
        viewModel.select(day: paris(2026, 12, 2))
        #expect(viewModel.displayedMonth == paris(2026, 12, 1))
    }
}

@MainActor
struct InfoViewModelTests {
    func makeViewModel(now: Date) async -> InfoViewModel {
        let viewModel = withDependencies {
            $0.date.now = now
            $0.libraryClient.libraries = { SampleData.libraries.reversed() }
        } operation: {
            InfoViewModel()
        }
        await viewModel.load()
        return viewModel
    }

    @Test func librariesAreSortedAndStatusComputed() async throws {
        // Vendredi 30 octobre 2026 à 20:00, après la fermeture.
        let viewModel = await makeViewModel(now: paris(2026, 10, 30, 20))
        let libraries = try #require(viewModel.state.value)
        #expect(libraries.map(\.library) == [.elsaTriolet, .pulpSud, .pulpNord])
        #expect(viewModel.statusText(of: libraries[0]) == "Fermé · ouvre demain à 10:00")
        #expect(!viewModel.isOpen(libraries[0]))
    }

    @Test func openStatus() async throws {
        // Mercredi 4 novembre 2026 à 11:00.
        let viewModel = await makeViewModel(now: paris(2026, 11, 4, 11))
        let elsa = try #require(viewModel.state.value?.first)
        #expect(viewModel.statusText(of: elsa) == "Ouvert · ferme à 19:00")
        #expect(viewModel.isToday("Mercredi : 10h - 19h"))
    }
}

@MainActor
struct AgendaPeriodTests {
    // Jeudi 29 octobre 2026, pendant les vacances de la Toussaint.
    let thursday = paris(2026, 10, 29, 9)

    func makeViewModel(period: AgendaPeriod) async -> AgendaViewModel {
        let viewModel = withDependencies {
            $0.date.now = thursday
            $0.agendaClient.events = { SampleData.events }
        } operation: { AgendaViewModel() }
        await viewModel.load()
        viewModel.filters.period = period
        return viewModel
    }

    @Test func weekendDays() {
        #expect(AgendaPeriod.weekend.days(from: thursday, calendar: .paris) == [paris(2026, 10, 31), paris(2026, 11, 1)])
        #expect(AgendaPeriod.weekend.days(from: paris(2026, 10, 31, 15), calendar: .paris) == [paris(2026, 10, 31), paris(2026, 11, 1)])
        #expect(AgendaPeriod.weekend.days(from: paris(2026, 11, 1, 15), calendar: .paris) == [paris(2026, 11, 1)])
        #expect(AgendaPeriod.all.days(from: thursday, calendar: .paris).isEmpty)
    }

    @Test func wednesdaysStartAtTheNextOne() {
        let days = AgendaPeriod.wednesdays.days(from: thursday, calendar: .paris)
        #expect(days.count == AgendaPeriod.wednesdayWeeks)
        #expect(days.first == paris(2026, 11, 4))
        #expect(AgendaPeriod.wednesdays.days(from: paris(2026, 11, 4, 8), calendar: .paris).first == paris(2026, 11, 4))
    }

    @Test func schoolHolidaysAreTheCurrentOrNextOnes() {
        let toussaint = AgendaPeriod.schoolHolidays.days(from: thursday, calendar: .paris)
        #expect(toussaint == [paris(2026, 10, 29), paris(2026, 10, 30), paris(2026, 10, 31), paris(2026, 11, 1)])

        let christmas = AgendaPeriod.schoolHolidays.days(from: paris(2026, 11, 3), calendar: .paris)
        #expect(christmas.first == paris(2026, 12, 19))
        #expect(christmas.last == paris(2027, 1, 3))
    }

    @Test func weekendGroupsEventsByDay() async {
        let viewModel = await makeViewModel(period: .weekend)
        #expect(viewModel.periodDays.map(\.day) == [paris(2026, 10, 31)])
        #expect(viewModel.periodDays.first?.events.map(\.id) == [990])
        #expect(viewModel.periodOngoingEvents.map(\.id) == [983])
        #expect(viewModel.filters.count == 1)
    }

    @Test func countIncludesThePeriod() async {
        let viewModel = await makeViewModel(period: .all)
        var filters = AgendaFilters()
        filters.period = .wednesdays
        // La conférence du mercredi 4 et le prix, qui couvre tous les mercredis.
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
