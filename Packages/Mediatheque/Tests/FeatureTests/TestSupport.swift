// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import MediathequeCore

/// A date in Paris, noon by default: far from midnight, a day never shifts with the time zone.
func paris(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    // Valid components: the calendar always returns a date.
    Calendar.paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Empty settings of their own for each test, so none sees another's.
func freshDefaults() -> UserDefaults {
    // A new suite name is always accepted.
    UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
}
