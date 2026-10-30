import Foundation

/// Dernier état connu du compte, partagé avec le widget par l'App Group.
/// C'est la seule persistance de l'app : un fichier JSON, pas de base de données.
public struct AccountSnapshot: Codable, Hashable, Sendable {
    public var loans: [Loan]
    public var holds: [Hold]
    public var updatedAt: Date

    public init(loans: [Loan], holds: [Hold], updatedAt: Date) {
        self.loans = loans
        self.holds = holds
        self.updatedAt = updatedAt
    }

    /// Prochains retours, du plus urgent au plus lointain.
    public var upcomingLoans: [Loan] {
        loans.sorted { $0.dueDate < $1.dueDate }
    }

    /// Réservations devenues disponibles depuis `previous` (pour la notification « vous attend »).
    public func newlyReadyHolds(since previous: AccountSnapshot?) -> [Hold] {
        let wasReady = Set(previous?.holds.filter(\.isReadyForPickup).map(\.id) ?? [])
        return holds.filter { $0.isReadyForPickup && !wasReady.contains($0.id) }
    }
}

/// Rappel local à programmer.
public struct Reminder: Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public enum ReminderPlanner {
    /// Heure d'envoi des rappels de retour.
    static let hour = 10

    /// Un rappel `daysBefore` jours avant chaque retour, et un le jour même. Seuls les rappels futurs sont gardés.
    public static func loanReminders(for loans: [Loan], daysBefore: Int, now: Date, calendar: Calendar) -> [Reminder] {
        // Les prêts qui tombent le même jour partagent un seul rappel.
        let byDay = Dictionary(grouping: loans) { calendar.startOfDay(for: $0.dueDate) }
        return byDay.flatMap { day, loans -> [Reminder] in
            let titles = loans.map(\.title)
            let what = titles.count == 1 ? "« \(titles[0]) »" : "\(titles.count) documents"
            var reminders: [Reminder] = []
            if let before = calendar.date(byAdding: .day, value: -daysBefore, to: day),
               let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: before) {
                reminders.append(Reminder(
                    id: "loan-before-\(Int(day.timeIntervalSince1970))",
                    title: "À rendre dans \(daysBefore) jours",
                    body: "\(what) à rendre le \(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))). Vous pouvez prolonger depuis l'app.",
                    fireDate: fire
                ))
            }
            if let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                reminders.append(Reminder(
                    id: "loan-due-\(Int(day.timeIntervalSince1970))",
                    title: "À rendre aujourd'hui",
                    body: "\(what) à rendre aujourd'hui. Prolongez-le si vous n'avez pas fini.",
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
            title: "\(hold.title) vous attend",
            body: "À retirer à \(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName). \(hold.statusText)",
            fireDate: .now
        )
    }
}
