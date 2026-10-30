import Foundation

public struct Event: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let imageURL: URL?
    public let place: String?
    public let library: Library?
    public let start: Date?
    public let end: Date?
    /// Vrai pour un événement sur plusieurs jours sans horaire (exposition, prix…).
    public let isAllDay: Bool
    public let type: String?
    public let audience: String?
    /// Phrase du site, par exemple « Samedi 31 octobre 2026 de 10:30 à 11:00 ».
    public let dateDescription: String?

    /// Vrai si l'événement a lieu, au moins en partie, le jour de `date`.
    public func occurs(on date: Date, calendar: Calendar) -> Bool {
        guard let start else { return false }
        let day = calendar.startOfDay(for: date)
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end ?? start)
        return first <= day && day <= last
    }
}

public struct EventDetail: Hashable, Sendable {
    public let event: Event
    public let descriptionText: String?
    public let latitude: Double?
    public let longitude: Double?
}
