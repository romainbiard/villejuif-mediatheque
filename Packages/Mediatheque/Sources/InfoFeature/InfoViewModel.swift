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

    public func load() async {
        if state.value == nil { state = .loading }
        do {
            let libraries = try await libraryClient.libraries()
            // Les 3 médiathèques dans l'ordre du réseau.
            state = .loaded(libraries.sorted { ($0.library?.rawValue ?? "9") < ($1.library?.rawValue ?? "9") })
        } catch {
            if state.value == nil { state = .failed(LoadError(error)) }
        }
    }

    public func status(of library: LibraryInfo) -> OpeningHours.Status {
        library.hours.status(at: now, calendar: calendar)
    }

    /// « Ouvert · ferme à 19:00 », « Fermé · ouvre samedi à 10:00 ».
    public func statusText(of library: LibraryInfo) -> String {
        switch status(of: library) {
        case let .open(closesAt):
            return "Ouvert · ferme à \(closesAt.formatted(Self.time))"
        case let .closed(reopensAt?):
            let sameDay = calendar.isDate(reopensAt, inSameDayAs: now)
            // Par rapport à `now` (injecté), pas à l'horloge du système.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).map { calendar.isDate(reopensAt, inSameDayAs: $0) } ?? false
            let day = sameDay ? "" : tomorrow ? "demain " : "\(reopensAt.formatted(.dateTime.weekday(.wide))) "
            return "Fermé · ouvre \(day)à \(reopensAt.formatted(Self.time))"
        case .closed(nil):
            return "Fermé"
        }
    }

    public func isOpen(_ library: LibraryInfo) -> Bool {
        if case .open = status(of: library) { return true }
        return false
    }

    /// Ligne d'horaires du jour, mise en avant dans la liste.
    public func isToday(_ line: String) -> Bool {
        let weekday = now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
        return line.lowercased().hasPrefix(weekday.lowercased())
    }

    static let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
}
