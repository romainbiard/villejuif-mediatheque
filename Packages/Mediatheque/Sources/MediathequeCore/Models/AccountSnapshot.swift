// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Last known state of the account, shared with the widget through the App Group.
/// This is the app's only persistence: a JSON file, no database.
public struct AccountSnapshot: Codable, Hashable, Sendable {
    public var loans: [Loan]
    public var holds: [Hold]
    public var updatedAt: Date

    public init(loans: [Loan], holds: [Hold], updatedAt: Date) {
        self.loans = loans
        self.holds = holds
        self.updatedAt = updatedAt
    }

    /// Upcoming returns, most urgent first.
    public var upcomingLoans: [Loan] {
        loans.sorted { $0.dueDate < $1.dueDate }
    }

    /// Holds that became available since `previous` (for the "vous attend" notification).
    public func newlyReadyHolds(since previous: AccountSnapshot?) -> [Hold] {
        let wasReady = Set(previous?.holds.filter(\.isReadyForPickup).map(\.id) ?? [])
        return holds.filter { $0.isReadyForPickup && !wasReady.contains($0.id) }
    }
}

/// Local reminder to schedule.
public struct Reminder: Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public enum ReminderPlanner {
    /// Time at which due-date reminders are sent.
    static let hour = 10

    /// One reminder `daysBefore` days before each due date, and one on the day itself. Only future reminders are kept.
    public static func loanReminders(for loans: [Loan], daysBefore: Int, now: Date, calendar: Calendar) -> [Reminder] {
        // Loans due on the same day share a single reminder.
        let byDay = Dictionary(grouping: loans) { calendar.startOfDay(for: $0.dueDate) }
        return byDay.flatMap { day, loans -> [Reminder] in
            let titles = loans.map(\.title)
            let what: String = titles.count == 1 ? .local("« \(titles[0]) »") : .local("\(titles.count) documents")
            let dayText = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            var reminders: [Reminder] = []
            if let before = calendar.date(byAdding: .day, value: -daysBefore, to: day),
               let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: before) {
                reminders.append(Reminder(
                    id: "loan-before-\(Int(day.timeIntervalSince1970))",
                    title: .local("À rendre dans \(daysBefore) jours"),
                    body: .local("\(what) à rendre le \(dayText). Vous pouvez prolonger depuis l'app."),
                    fireDate: fire
                ))
            }
            if let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                reminders.append(Reminder(
                    id: "loan-due-\(Int(day.timeIntervalSince1970))",
                    title: .local("À rendre aujourd'hui"),
                    body: .local("\(what) à rendre aujourd'hui. Prolongez-le si vous n'avez pas fini."),
                    fireDate: fire
                ))
            }
            return reminders
        }
        .filter { $0.fireDate > now }
        .sorted { $0.fireDate < $1.fireDate }
    }

    public static func holdReadyReminder(for hold: Hold) -> Reminder {
        Reminder(
            id: "hold-ready-\(hold.id)",
            // Generic title: the document's title only in the body, hidden on the Lock Screen when previews are.
            title: .local("Une réservation vous attend"),
            body: .local("« \(hold.title) » est à retirer à \(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName). \(hold.statusText)"),
            fireDate: .now
        )
    }
}
