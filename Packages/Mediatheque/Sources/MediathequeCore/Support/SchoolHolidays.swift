// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// School holidays for zone C (Créteil academy), embedded in the app.
/// Source: data.education.gouv.fr, dataset "fr-en-calendrier-scolaire", retrieved on 31/10/2026.
/// To be updated every year when the ministry publishes the next calendar.
public struct SchoolHoliday: Hashable, Sendable {
    public let name: String
    /// First day of the holidays, at midnight in Paris.
    public let start: Date
    /// Day school resumes (excluded).
    public let end: Date
}

public enum SchoolHolidays {
    public static let zoneC: [SchoolHoliday] = [
        holiday(.local("Vacances de la Toussaint"), (2026, 10, 17), (2026, 11, 2)),
        holiday(.local("Vacances de Noël"), (2026, 12, 19), (2027, 1, 4)),
        holiday(.local("Vacances d'hiver"), (2027, 2, 6), (2027, 2, 22)),
        holiday(.local("Vacances de printemps"), (2027, 4, 3), (2027, 4, 19)),
        holiday(.local("Pont de l'Ascension"), (2027, 5, 7), (2027, 5, 8)),
        holiday(.local("Vacances d'été"), (2027, 7, 3), (2027, 9, 2)),
        holiday(.local("Vacances de la Toussaint"), (2027, 10, 23), (2027, 11, 8)),
        holiday(.local("Vacances de Noël"), (2027, 12, 18), (2028, 1, 3)),
        holiday(.local("Vacances d'hiver"), (2028, 2, 12), (2028, 2, 28)),
        holiday(.local("Vacances de printemps"), (2028, 4, 15), (2028, 5, 2)),
        holiday(.local("Pont de l'Ascension"), (2028, 5, 25), (2028, 5, 29)),
        // Only the start is published: the 2028 school year is assumed to start on September 1.
        holiday(.local("Vacances d'été"), (2028, 7, 4), (2028, 9, 1))
    ]

    /// The holidays in progress at `date`, otherwise the next ones.
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
