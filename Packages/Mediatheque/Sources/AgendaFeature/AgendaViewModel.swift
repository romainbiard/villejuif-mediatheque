import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Filtres de l'agenda, appliqués localement : une seule requête ramène tous les événements.
public struct AgendaFilters: Hashable, Sendable {
    public var places: Set<String> = []
    public var types: Set<String> = []
    public var audiences: Set<String> = []

    public init() {}

    public var count: Int { places.count + types.count + audiences.count }
    public var isEmpty: Bool { count == 0 }

    func matches(_ event: Event) -> Bool {
        (places.isEmpty || event.place.map(places.contains) == true)
            && (types.isEmpty || event.type.map(types.contains) == true)
            && (audiences.isEmpty || event.audience.map(audiences.contains) == true)
    }
}

@MainActor
@Observable
public final class AgendaViewModel {
    public private(set) var state: LoadState<[Event]> = .idle
    public private(set) var selectedDay: Date
    public var filters = AgendaFilters() {
        didSet { feedback = .selection }
    }
    public private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.agendaClient) private var agenda
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored let calendar = Calendar.paris

    static let visibleDays = 14

    public init() {
        @Dependency(\.date.now) var now
        selectedDay = Calendar.paris.startOfDay(for: now)
    }

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await agenda.events())
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public func select(day: Date) {
        guard !calendar.isDate(day, inSameDayAs: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: day)
        feedback = .selection
    }

    public func clearFilters() {
        filters = AgendaFilters()
    }

    // MARK: Données dérivées

    /// Les 14 prochains jours, pour le sélecteur.
    public var days: [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<Self.visibleDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var filteredEvents: [Event] {
        (state.value ?? []).filter(filters.matches)
    }

    /// Événements horaires du jour choisi.
    public var eventsOfSelectedDay: [Event] {
        filteredEvents.filter { !$0.isAllDay && $0.occurs(on: selectedDay, calendar: calendar) }
    }

    /// Expositions, prix… qui couvrent le jour choisi.
    public var ongoingEvents: [Event] {
        filteredEvents.filter { $0.isAllDay && $0.occurs(on: selectedDay, calendar: calendar) }
    }

    /// Vrai si un jour du sélecteur a au moins un événement horaire (point sous la date).
    public func hasEvents(on day: Date) -> Bool {
        filteredEvents.contains { !$0.isAllDay && $0.occurs(on: day, calendar: calendar) }
    }

    /// Prochain jour avec un événement après le jour choisi, pour l'état vide.
    public var nextDayWithEvents: Date? {
        filteredEvents
            .compactMap { event -> Date? in
                guard !event.isAllDay, let start = event.start else { return nil }
                let day = calendar.startOfDay(for: start)
                return day > selectedDay ? day : nil
            }
            .min()
    }

    /// Nombre d'événements à venir avec les filtres en cours (bouton « Voir N événements »).
    public func upcomingCount(with filters: AgendaFilters) -> Int {
        let today = calendar.startOfDay(for: now)
        return (state.value ?? []).filter { event in
            filters.matches(event) && (event.end ?? event.start).map { $0 >= today } == true
        }.count
    }

    public var availablePlaces: [String] { distinct(\.place, prioritizing: Library.allCases.map(\.shortName)) }
    public var availableTypes: [String] { distinct(\.type) }
    public var availableAudiences: [String] { distinct(\.audience) }

    /// Le réseau est fermé le dimanche et le lundi.
    public func isLibraryClosingDay(_ day: Date) -> Bool {
        [1, 2].contains(calendar.component(.weekday, from: day))
    }

    private func distinct(_ keyPath: KeyPath<Event, String?>, prioritizing first: [String] = []) -> [String] {
        let values = Set((state.value ?? []).compactMap { $0[keyPath: keyPath] })
        let priority = { (value: String) in
            first.firstIndex { value.localizedCaseInsensitiveContains($0) } ?? first.count
        }
        return values.sorted { (priority($0), $0) < (priority($1), $1) }
    }
}

@MainActor
@Observable
public final class EventDetailViewModel {
    public let event: Event
    public private(set) var detail: LoadState<EventDetail> = .idle

    @ObservationIgnored @Dependency(\.agendaClient) private var agenda

    public init(event: Event) {
        self.event = event
    }

    public func load() async {
        detail = .loading
        do {
            detail = .loaded(try await agenda.detail(event))
        } catch {
            detail = .failed(LoadError(error))
        }
    }

    /// Lien iCal du site, pour l'ajout au calendrier.
    public var iCalURL: URL {
        URL(string: "https://mediatheque.villejuif.fr/cms/ical/id_article/\(event.id)")!
    }
}
