// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

public struct Event: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let title: String
    public let imageURL: URL?
    public let place: String?
    public let library: Library?
    public let start: Date?
    public let end: Date?
    /// True for a multi-day event with no time (exhibition, award…).
    public let isAllDay: Bool
    public let type: String?
    public let audience: String?
    /// Sentence from the site, e.g. "Samedi 31 octobre 2026 de 10:30 à 11:00".
    public let dateDescription: String?

    /// True if the event takes place, at least partly, on the day of `date`.
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
