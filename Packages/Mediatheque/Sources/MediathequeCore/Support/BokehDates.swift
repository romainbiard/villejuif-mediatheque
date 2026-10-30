import Foundation

/// Formats de date rencontrés sur le portail, tous en heure de Paris.
enum BokehDates {
    static let parisTimeZone = TimeZone(identifier: "Europe/Paris")!

    static var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = parisTimeZone
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    /// `2026-11-20` (API JSON).
    static func isoDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return nil }
        return parisCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// `31/10/2026` ou `31/10/2026 à 10:30` (HTML). Renvoie aussi si une heure était présente.
    static func frenchDate(_ string: String) -> (date: Date, hasTime: Bool)? {
        guard let match = string.firstMatch(of: /(\d{2})\/(\d{2})\/(\d{4})(?:\s+à\s+(\d{1,2}):(\d{2}))?/) else { return nil }
        var components = DateComponents(year: Int(match.3), month: Int(match.2), day: Int(match.1))
        let hasTime = match.4 != nil
        if let hour = match.4, let minute = match.5 {
            components.hour = Int(hour)
            components.minute = Int(minute)
        }
        guard let date = parisCalendar.date(from: components) else { return nil }
        return (date, hasTime)
    }

    /// Première date `jj/mm/aaaa` d'un texte libre (« Pas disponible avant le 14/11/2026 »).
    static func firstDate(in text: String) -> Date? {
        frenchDate(text)?.date
    }
}

extension Calendar {
    /// Calendrier grégorien en heure de Paris et en français, celui des horaires et de l'agenda.
    public static var paris: Calendar { BokehDates.parisCalendar }
}
