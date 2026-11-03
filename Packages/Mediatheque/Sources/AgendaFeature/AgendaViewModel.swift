// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

/// "Quand": computed in the app, the website has no such filter.
enum AgendaPeriod: String, CaseIterable, Hashable, Identifiable {
    case all, weekend, wednesdays, schoolHolidays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: .local("Tout", comment: "Agenda period filter: no date restriction")
        case .weekend: .local("Ce week-end")
        case .wednesdays: .local("Mercredis", comment: "Agenda period filter")
        case .schoolHolidays: .local("Vacances scolaires")
        }
    }

    /// Wednesdays kept: the next 8 weeks.
    static let wednesdayWeeks = 8

    /// Days covered, starting today. Empty for `.all`.
    func days(from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        func adding(_ days: Int, to date: Date) -> Date? { calendar.date(byAdding: .day, value: days, to: date) }
        switch self {
        case .all:
            return []
        case .weekend:
            // The coming Saturday and Sunday, or the current weekend.
            let weekday = calendar.component(.weekday, from: today)
            if weekday == 1 { return [today] }
            guard let saturday = adding((7 - weekday) % 7, to: today) else { return [] }
            return [saturday, adding(1, to: saturday)].compactMap(\.self)
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

/// Agenda filters, applied locally: a single request fetches all events.
struct AgendaFilters: Hashable {
    var places: Set<String> = []
    var types: Set<String> = []
    var audiences: Set<String> = []
    var period: AgendaPeriod = .all

    var count: Int { places.count + types.count + audiences.count + (period == .all ? 0 : 1) }
    var isEmpty: Bool { count == 0 }

    func matches(_ event: Event) -> Bool {
        (places.isEmpty || event.place.map(places.contains) == true)
            && (types.isEmpty || event.type.map(types.contains) == true)
            && (audiences.isEmpty || event.audience.map(audiences.contains) == true)
    }
}

@MainActor
@Observable
final class AgendaViewModel {
    private(set) var state: LoadState<[Event]> = .idle
    /// The portal didn't answer: the agenda on screen is the last one saved.
    private(set) var staleError: LoadError?
    private(set) var selectedDay: Date
    /// First day of the month shown by the mini calendar (iPad).
    private(set) var displayedMonth: Date
    var filters = AgendaFilters() {
        didSet { feedback = .selection }
    }

    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.agendaClient) private var agenda
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored let calendar = Calendar.paris

    static let visibleDays = 14

    init() {
        @Dependency(\.date.now) var now
        selectedDay = Calendar.paris.startOfDay(for: now)
        displayedMonth = Calendar.paris.dateInterval(of: .month, for: now)?.start ?? now
    }

    /// `.reload` for pull-to-refresh: bypasses the cache, without losing the list on failure.
    func load(_ policy: CachePolicy = .useCache) async {
        if state.value == nil { state = .loading }
        do {
            let events = try await agenda.events(policy)
            state = .loaded(events.value)
            staleError = events.refreshError
        } catch {
            if state.value == nil {
                state = .failed(LoadError(error))
            } else {
                staleError = LoadError(error)
            }
        }
    }

    func select(day: Date) {
        guard !calendar.isDate(day, inSameDayAs: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: day)
        if let month = calendar.dateInterval(of: .month, for: day)?.start { displayedMonth = month }
        feedback = .selection
    }

    // MARK: Mini calendar (iPad)

    /// Cells of the displayed month, Monday first: `nil` for the leading empty cells.
    var monthGrid: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        // weekday: 1 = Sunday; offset so the week starts on Monday.
        let leading = (calendar.component(.weekday, from: displayedMonth) + 5) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: displayedMonth) }
        return Array(repeating: nil, count: leading) + days
    }

    /// No going back before the current month: the agenda only shows the future.
    var canShowPreviousMonth: Bool {
        guard let current = calendar.dateInterval(of: .month, for: now)?.start else { return false }
        return displayedMonth > current
    }

    func showPreviousMonth() {
        guard canShowPreviousMonth else { return }
        moveMonth(by: -1)
    }

    func showNextMonth() {
        moveMonth(by: 1)
    }

    /// Past days cannot be selected.
    func isSelectable(_ day: Date) -> Bool {
        day >= calendar.startOfDay(for: now)
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = month
        feedback = .selection
    }

    func clearFilters() {
        filters = AgendaFilters()
    }

    // MARK: Derived data

    /// The next 14 days, for the picker.
    var days: [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<Self.visibleDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var filteredEvents: [Event] {
        (state.value ?? []).filter(filters.matches)
    }

    /// Timed events on the selected day.
    var eventsOfSelectedDay: [Event] {
        filteredEvents.filter { !$0.isAllDay && $0.occurs(on: selectedDay, calendar: calendar) }
    }

    /// Exhibitions, prizes… that span the selected day.
    var ongoingEvents: [Event] {
        filteredEvents.filter { $0.isAllDay && $0.occurs(on: selectedDay, calendar: calendar) }
    }

    /// True if a picker day has at least one timed event (dot under the date).
    func hasEvents(on day: Date) -> Bool {
        filteredEvents.contains { !$0.isAllDay && $0.occurs(on: day, calendar: calendar) }
    }

    /// Next day with an event after the selected day, for the empty state.
    var nextDayWithEvents: Date? {
        filteredEvents
            .compactMap { event -> Date? in
                guard !event.isAllDay, let start = event.start else { return nil }
                let day = calendar.startOfDay(for: start)
                return day > selectedDay ? day : nil
            }
            .min()
    }

    /// Number of upcoming events with the current filters ("Voir N événements" button).
    func upcomingCount(with filters: AgendaFilters) -> Int {
        let today = calendar.startOfDay(for: now)
        let periodDays = filters.period.days(from: now, calendar: calendar)
        return (state.value ?? []).count(where: { event in
            guard filters.matches(event), (event.end ?? event.start).map({ $0 >= today }) == true else { return false }
            return filters.period == .all || periodDays.contains { event.occurs(on: $0, calendar: calendar) }
        })
    }

    // MARK: Period ("Quand")

    /// One day of the selected period, with its timed events.
    struct PeriodDay: Identifiable, Equatable {
        let day: Date
        let events: [Event]
        var id: Date { day }
    }

    /// Days of the period that have at least one timed event.
    var periodDays: [PeriodDay] {
        filters.period.days(from: now, calendar: calendar).compactMap { day in
            let events = filteredEvents.filter { !$0.isAllDay && $0.occurs(on: day, calendar: calendar) }
            return events.isEmpty ? nil : PeriodDay(day: day, events: events)
        }
    }

    /// Exhibitions and long events that span at least one day of the period.
    var periodOngoingEvents: [Event] {
        let days = filters.period.days(from: now, calendar: calendar)
        return filteredEvents.filter { event in event.isAllDay && days.contains { event.occurs(on: $0, calendar: calendar) } }
    }

    /// Label under the title: "Samedi 31 octobre et dimanche 1er novembre", "Vacances de Noël"…
    var periodSummary: String? {
        let days = filters.period.days(from: now, calendar: calendar)
        switch filters.period {
        case .all:
            return nil
        case .weekend:
            let names = days.map { $0.parisFormatted(.dateTime.weekday(.wide).day().month(.wide)) }
            return names.count == 2 ? String.local("\(names[0]) et \(names[1])", comment: "Two days of a weekend") : names.first
        case .wednesdays:
            return String.local("Les \(AgendaPeriod.wednesdayWeeks) prochains mercredis")
        case .schoolHolidays:
            guard let holiday = SchoolHolidays.currentOrNext(after: calendar.startOfDay(for: now)),
                  let last = calendar.date(byAdding: .day, value: -1, to: holiday.end)
            else { return nil }
            let start = holiday.start.parisFormatted(.dateTime.day().month(.wide))
            let end = last.parisFormatted(.dateTime.day().month(.wide))
            return String.local("\(holiday.name), du \(start) au \(end)", comment: "School holidays name, first day, last day")
        }
    }

    func clearPeriod() {
        filters.period = .all
    }

    var availablePlaces: [String] { distinct(\.place, prioritizing: Library.allCases.map(\.shortName)) }
    var availableTypes: [String] { distinct(\.type) }
    var availableAudiences: [String] { distinct(\.audience) }

    /// The network is closed on Sundays and Mondays.
    func isLibraryClosingDay(_ day: Date) -> Bool {
        [1, 2].contains(calendar.component(.weekday, from: day))
    }

    /// What the day's dot and grey say, read out by VoiceOver: "Des animations", "Médiathèques fermées".
    func accessibilityValue(for day: Date) -> String {
        [
            hasEvents(on: day) ? String.local("Des animations", comment: "VoiceOver: the day has events") : nil,
            isLibraryClosingDay(day) ? String.local("Médiathèques fermées", comment: "VoiceOver: the libraries are closed that day") : nil
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
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
final class EventDetailViewModel {
    let event: Event
    private(set) var detail: LoadState<EventDetail> = .idle

    @ObservationIgnored @Dependency(\.agendaClient) private var agenda

    init(event: Event) {
        self.event = event
    }

    func load() async {
        detail = .loading
        do {
            detail = try await .loaded(agenda.detail(event))
        } catch {
            detail = .failed(LoadError(error))
        }
    }

    /// The website's iCal link, for adding to the calendar.
    var iCalURL: URL {
        URL(string: "https://mediatheque.villejuif.fr/cms/ical/id_article/\(event.id)")!
    }
}
