import Foundation

/// Vacances scolaires de la zone C (académie de Créteil), embarquées dans l'app.
/// Source : data.education.gouv.fr, jeu « fr-en-calendrier-scolaire », relevé le 31/10/2026.
/// À compléter chaque année quand le ministère publie le calendrier suivant.
public struct SchoolHoliday: Hashable, Sendable {
    public let name: String
    /// Premier jour de vacances, à minuit à Paris.
    public let start: Date
    /// Jour de la reprise (exclu).
    public let end: Date

    public func contains(_ date: Date) -> Bool { start <= date && date < end }
}

public enum SchoolHolidays {
    public static let zoneC: [SchoolHoliday] = [
        holiday("Vacances de la Toussaint", (2026, 10, 17), (2026, 11, 2)),
        holiday("Vacances de Noël", (2026, 12, 19), (2027, 1, 4)),
        holiday("Vacances d'hiver", (2027, 2, 6), (2027, 2, 22)),
        holiday("Vacances de printemps", (2027, 4, 3), (2027, 4, 19)),
        holiday("Pont de l'Ascension", (2027, 5, 7), (2027, 5, 8)),
        holiday("Vacances d'été", (2027, 7, 3), (2027, 9, 2)),
        holiday("Vacances de la Toussaint", (2027, 10, 23), (2027, 11, 8)),
        holiday("Vacances de Noël", (2027, 12, 18), (2028, 1, 3)),
        holiday("Vacances d'hiver", (2028, 2, 12), (2028, 2, 28)),
        holiday("Vacances de printemps", (2028, 4, 15), (2028, 5, 2)),
        holiday("Pont de l'Ascension", (2028, 5, 25), (2028, 5, 29)),
        // Seul le début est publié : la rentrée 2028 est supposée au 1er septembre.
        holiday("Vacances d'été", (2028, 7, 4), (2028, 9, 1)),
    ]

    /// Les vacances en cours à `date`, sinon les prochaines.
    public static func currentOrNext(after date: Date, in holidays: [SchoolHoliday] = zoneC) -> SchoolHoliday? {
        holidays.first { $0.end > date }
    }

    private static func holiday(_ name: String, _ start: (Int, Int, Int), _ end: (Int, Int, Int)) -> SchoolHoliday {
        func day(_ value: (Int, Int, Int)) -> Date {
            Calendar.paris.date(from: DateComponents(year: value.0, month: value.1, day: value.2))!
        }
        return SchoolHoliday(name: name, start: day(start), end: day(end))
    }
}
