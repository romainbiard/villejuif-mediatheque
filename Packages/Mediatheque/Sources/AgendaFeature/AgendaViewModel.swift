import Dependencies
import Foundation
import MediathequeCore
import Observation

/// « Quand » : calculé dans l'app, le site n'a pas ce filtre.
public enum AgendaPeriod: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all, weekend, wednesdays, schoolHolidays

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "Tout"
        case .weekend: "Ce week-end"
        case .wednesdays: "Mercredis"
        case .schoolHolidays: "Vacances scolaires"
        }
    }

    /// Mercredis gardés : les 8 prochaines semaines.
    static let wednesdayWeeks = 8

    /// Jours couverts, à partir d'aujourd'hui. Vide pour `.all`.
    public func days(from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        func adding(_ days: Int, to date: Date) -> Date? { calendar.date(byAdding: .day, value: days, to: date) }
        switch self {
        case .all:
            return []
        case .weekend:
            // Samedi et dimanche qui viennent, ou le week-end en cours.
            let weekday = calendar.component(.weekday, from: today)
            if weekday == 1 { return [today] }
            guard let saturday = adding((7 - weekday) % 7, to: today) else { return [] }
            return [saturday, adding(1, to: saturday)].compactMap { $0 }
        case .wednesdays:
            let weekday = calendar.component(.weekday, from: today)
            guard let first = adding((4 - weekday + 7) % 7, to: today) else { return [] }
            return (0..<Self.wednesdayWeeks).compactMap { adding($0 * 7, to: first) }
        case .schoolHolidays:
            guard let holiday = SchoolHolidays.currentOrNext(after: today) else { return [] }
            var days: [Date] = []
            var day = max(holiday.start, today)
            while day < holiday.end, let next = adding(1, to: day) {
                days.append(day)
                day = next
            }
            return days
        }
    }
}

/// Filtres de l'agenda, appliqués localement : une seule requête ramène tous les événements.
public struct AgendaFilters: Hashable, Sendable {
    public var places: Set<String> = []
    public var types: Set<String> = []
    public var audiences: Set<String> = []
    public var period: AgendaPeriod = .all

    public init() {}

    public var count: Int { places.count + types.count + audiences.count + (period == .all ? 0 : 1) }
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
        let periodDays = filters.period.days(from: now, calendar: calendar)
        return (state.value ?? []).filter { event in
            guard filters.matches(event), (event.end ?? event.start).map({ $0 >= today }) == true else { return false }
            return filters.period == .all || periodDays.contains { event.occurs(on: $0, calendar: calendar) }
        }.count
    }

    // MARK: Période (« Quand »)

    /// Une journée de la période choisie, avec ses événements horaires.
    public struct PeriodDay: Identifiable, Equatable {
        public let day: Date
        public let events: [Event]
        public var id: Date { day }
    }

    /// Jours de la période qui ont au moins un événement horaire.
    public var periodDays: [PeriodDay] {
        filters.period.days(from: now, calendar: calendar).compactMap { day in
            let events = filteredEvents.filter { !$0.isAllDay && $0.occurs(on: day, calendar: calendar) }
            return events.isEmpty ? nil : PeriodDay(day: day, events: events)
        }
    }

    /// Expositions et événements longs qui couvrent au moins un jour de la période.
    public var periodOngoingEvents: [Event] {
        let days = filters.period.days(from: now, calendar: calendar)
        return filteredEvents.filter { event in event.isAllDay && days.contains { event.occurs(on: $0, calendar: calendar) } }
    }

    /// Libellé sous le titre : « Samedi 31 octobre et dimanche 1er novembre », « Vacances de Noël »…
    public var periodSummary: String? {
        let french = Locale(identifier: "fr_FR")
        let days = filters.period.days(from: now, calendar: calendar)
        switch filters.period {
        case .all:
            return nil
        case .weekend:
            return days.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french)) }
                .joined(separator: " et ")
        case .wednesdays:
            return "Les \(AgendaPeriod.wednesdayWeeks) prochains mercredis"
        case .schoolHolidays:
            guard let holiday = SchoolHolidays.currentOrNext(after: calendar.startOfDay(for: now)),
                  let last = calendar.date(byAdding: .day, value: -1, to: holiday.end)
            else { return nil }
            let range = "du \(holiday.start.formatted(.dateTime.day().month(.wide).locale(french))) au \(last.formatted(.dateTime.day().month(.wide).locale(french)))"
            return "\(holiday.name), \(range)"
        }
    }

    public func clearPeriod() {
        filters.period = .all
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
