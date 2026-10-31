import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Agenda : la liste vient du HTML du calendrier (l'API `/api/agenda` n'a pas les dates),
/// le détail de l'iCal de chaque événement.
@DependencyClient
public struct AgendaClient: Sendable {
    public var events: @Sendable (_ policy: CachePolicy) async throws -> [Event]
    public var detail: @Sendable (_ event: Event) async throws -> EventDetail
}

extension AgendaClient: DependencyKey {
    public static var liveValue: AgendaClient {
        @Dependency(\.httpClient) var http
        return AgendaClient(
            events: { policy in
                // Le site publie l'agenda une fois pour toutes : 30 min suffisent, et l'agenda reste lisible hors ligne.
                try await DataCache.shared.value(for: "agenda-events", maxAge: 30 * 60, policy: policy) {
                    try HTMLParsers.calendarEvents(in: try await http.string(for: .calendar()))
                        .map(Event.init(dto:))
                        .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                }
            },
            detail: { event in
                let ics = try await http.string(for: .eventICal(articleID: event.id))
                let vevent = ICalParser.events(from: ics).first
                return EventDetail(
                    event: event,
                    descriptionText: vevent?.descriptionText,
                    latitude: vevent?.latitude,
                    longitude: vevent?.longitude
                )
            }
        )
    }

    public static let previewValue = AgendaClient(
        events: { _ in SampleData.events },
        detail: { event in
            EventDetail(event: event, descriptionText: "Un moment de lecture partagé, en accès libre.", latitude: 48.7926, longitude: 2.3628)
        }
    )

    public static let testValue = AgendaClient()
}

/// Fiches pratiques des 3 médiathèques.
@DependencyClient
public struct LibraryClient: Sendable {
    public var libraries: @Sendable (_ policy: CachePolicy) async throws -> [LibraryInfo]
}

extension LibraryClient: DependencyKey {
    public static var liveValue: LibraryClient {
        @Dependency(\.httpClient) var http
        return LibraryClient(
            libraries: { policy in
                // Les horaires changent rarement (vacances, travaux) : 12 h, et toujours affichables hors ligne.
                try await DataCache.shared.value(for: "libraries", maxAge: 12 * 3600, policy: policy) {
                    try HTMLParsers.libraries(in: try await http.string(for: .practicalInfo)).map(LibraryInfo.init(dto:))
                }
            }
        )
    }

    public static let previewValue = LibraryClient(libraries: { _ in SampleData.libraries })
    public static let testValue = LibraryClient()
}

extension DependencyValues {
    public var agendaClient: AgendaClient {
        get { self[AgendaClient.self] }
        set { self[AgendaClient.self] = newValue }
    }

    public var libraryClient: LibraryClient {
        get { self[LibraryClient.self] }
        set { self[LibraryClient.self] = newValue }
    }
}
