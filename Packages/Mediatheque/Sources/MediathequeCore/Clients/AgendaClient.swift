// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Agenda: the list comes from the calendar HTML (the `/api/agenda` API has no dates),
/// the details from each event's iCal.
@DependencyClient
public struct AgendaClient: Sendable {
    public var events: @Sendable (_ policy: CachePolicy) async throws -> Cached<[Event]>
    public var detail: @Sendable (_ event: Event) async throws -> EventDetail
}

extension AgendaClient: DependencyKey {
    public static var liveValue: AgendaClient {
        @Dependency(\.httpClient) var http
        return AgendaClient(
            events: { policy in
                // The site publishes the agenda once and for all: 30 min is enough, and the agenda stays readable offline.
                try await DataCache.shared.cached(for: "agenda-events", maxAge: 30 * 60, policy: policy) {
                    try await HTMLParsers.calendarEvents(in: http.string(for: .calendar()))
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
        events: { _ in Cached(SampleData.events) },
        detail: { event in
            EventDetail(event: event, descriptionText: "Un moment de lecture partagé, en accès libre.", latitude: 48.7926, longitude: 2.3628)
        }
    )

    public static let testValue = AgendaClient()
}

/// Practical info for the 3 libraries.
@DependencyClient
public struct LibraryClient: Sendable {
    public var libraries: @Sendable (_ policy: CachePolicy) async throws -> Cached<[LibraryInfo]>
}

extension LibraryClient: DependencyKey {
    public static var liveValue: LibraryClient {
        @Dependency(\.httpClient) var http
        return LibraryClient(
            libraries: { policy in
                // Opening hours rarely change (holidays, works): 12 h, and always viewable offline.
                try await DataCache.shared.cached(for: "libraries", maxAge: 12 * 3600, policy: policy) {
                    try await HTMLParsers.libraries(in: http.string(for: .practicalInfo)).map(LibraryInfo.init(dto:))
                }
            }
        )
    }

    public static let previewValue = LibraryClient(libraries: { _ in Cached(SampleData.libraries) })
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
