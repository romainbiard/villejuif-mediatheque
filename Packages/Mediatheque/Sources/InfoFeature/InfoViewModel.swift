// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

@MainActor
@Observable
public final class InfoViewModel {
    public private(set) var state: LoadState<[LibraryInfo]> = .idle

    @ObservationIgnored @Dependency(\.libraryClient) private var libraryClient
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored let calendar = Calendar.paris

    public init() {}

    /// `.reload` for pull-to-refresh; otherwise the cached opening hours (12 h) show right away.
    public func load(_ policy: CachePolicy = .useCache) async {
        if state.value == nil { state = .loading }
        do {
            let libraries = try await libraryClient.libraries(policy)
            // The 3 libraries in network order.
            state = .loaded(libraries.sorted { ($0.library?.rawValue ?? "9") < ($1.library?.rawValue ?? "9") })
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public func status(of library: LibraryInfo) -> OpeningHours.Status {
        library.hours.status(at: now, calendar: calendar)
    }

    /// "Ouvert · ferme à 19:00", "Fermé · ouvre samedi à 10:00".
    public func statusText(of library: LibraryInfo) -> String {
        switch status(of: library) {
        case let .open(closesAt):
            return String.local("Ouvert · ferme à \(closesAt.formatted(Self.time))", comment: "Library status; %@ is a time")
        case let .closed(reopensAt?):
            let sameDay = calendar.isDate(reopensAt, inSameDayAs: now)
            // Relative to `now` (injected), not to the system clock.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).map { calendar.isDate(reopensAt, inSameDayAs: $0) } ?? false
            let time = reopensAt.formatted(Self.time)
            if sameDay { return String.local("Fermé · ouvre à \(time)", comment: "Library status; %@ is a time today") }
            if tomorrow { return String.local("Fermé · ouvre demain à \(time)", comment: "Library status; %@ is a time") }
            return String.local("Fermé · ouvre \(reopensAt.formatted(.dateTime.weekday(.wide))) à \(time)", comment: "Library status; weekday, time")
        case .closed(nil):
            return String.local("Fermé", comment: "Library status")
        }
    }

    public func isOpen(_ library: LibraryInfo) -> Bool {
        if case .open = status(of: library) { return true }
        return false
    }

    /// Today's opening-hours row, highlighted in the list.
    public func isToday(_ line: String) -> Bool {
        let weekday = now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
        return line.lowercased().hasPrefix(weekday.lowercased())
    }

    static let time = Date.FormatStyle.dateTime.hour().minute()
}
