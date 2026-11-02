// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// A library's regular opening hours, parsed from "Mardi : 13h - 19h".
public struct OpeningHours: Hashable, Sendable, Codable {
    public struct Slot: Hashable, Sendable, Codable {
        /// Minutes since midnight.
        public let opens: Int
        public let closes: Int
    }

    /// Time slots per weekday, as defined by `Calendar` (1 = Sunday … 7 = Saturday).
    public let slotsByWeekday: [Int: [Slot]]

    public init(slotsByWeekday: [Int: [Slot]]) {
        self.slotsByWeekday = slotsByWeekday
    }

    static let weekdays: [String: Int] = [
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7,
    ]

    /// Lines from the site: "Mardi : 13h - 19h", "Samedi : 10h - 12h30 / 14h - 18h".
    public init(lines: [String]) {
        var slots: [Int: [Slot]] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let weekday = Self.weekdays[parts[0].trimmingCharacters(in: .whitespaces).lowercased()]
            else { continue }
            let ranges = parts[1].matches(of: /(\d{1,2})h(\d{2})?\s*-\s*(\d{1,2})h(\d{2})?/)
            slots[weekday, default: []] += ranges.map { range in
                Slot(
                    opens: Int(range.1)! * 60 + (range.2.flatMap { Int($0) } ?? 0),
                    closes: Int(range.3)! * 60 + (range.4.flatMap { Int($0) } ?? 0)
                )
            }
        }
        self.slotsByWeekday = slots
    }

    public enum Status: Hashable, Sendable {
        case open(closesAt: Date)
        case closed(reopensAt: Date?)
    }

    /// Open or closed at `date`, and the time of the next change.
    public func status(at date: Date, calendar: Calendar) -> Status {
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let today = calendar.startOfDay(for: date)

        if let slot = slotsByWeekday[weekday]?.first(where: { $0.opens <= minutes && minutes < $0.closes }) {
            return .open(closesAt: today.addingTimeInterval(TimeInterval(slot.closes * 60)))
        }
        if let slot = slotsByWeekday[weekday]?.first(where: { minutes < $0.opens }) {
            return .closed(reopensAt: today.addingTimeInterval(TimeInterval(slot.opens * 60)))
        }
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let slot = slotsByWeekday[calendar.component(.weekday, from: day)]?.first
            else { continue }
            return .closed(reopensAt: day.addingTimeInterval(TimeInterval(slot.opens * 60)))
        }
        return .closed(reopensAt: nil)
    }

    /// Day with no time slot at all (Sunday and Monday for the network).
    public func isClosedAllDay(_ date: Date, calendar: Calendar) -> Bool {
        slotsByWeekday[calendar.component(.weekday, from: date)]?.isEmpty ?? true
    }
}

/// Practical info for a library.
public struct LibraryInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { library?.rawValue ?? slug }
    public let library: Library?
    public let slug: String
    public let name: String
    public let addressLines: [String]
    public let phone: String?
    public let contactURL: URL?
    public let hours: OpeningHours
    public let hourLines: [String]
}
