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
