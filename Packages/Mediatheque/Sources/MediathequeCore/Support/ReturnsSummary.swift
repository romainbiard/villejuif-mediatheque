// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Spoken answer to "Quand dois-je rendre mes livres ?" (Siri, Shortcuts, Spotlight).
/// Read from the on-device snapshot: no network, and nothing beyond what the widget card already shows.
public enum ReturnsSummary {
    /// Without a snapshot (never signed in, or signed out), prompts to sign in.
    public static func sentence(for snapshot: AccountSnapshot?, now: Date, calendar: Calendar) -> String {
        guard let snapshot else {
            return .local("Connectez-vous dans l'app Ma médiathèque pour suivre vos prêts.")
        }
        let loans = snapshot.upcomingLoans
        guard let first = loans.first else {
            return .local("Vous n'avez aucun prêt en cours.")
        }

        let late = loans.filter { if case .late = $0.dueState(now: now, calendar: calendar) { true } else { false } }
        if !late.isEmpty {
            let lateText: String = late.count == 1
                ? .local("« \(late[0].title) » est en retard.")
                : .local("\(late.count) documents sont en retard.")
            return "\(lateText) \(nextAfter(late, in: loans, now: now, calendar: calendar))"
                .trimmingCharacters(in: .whitespaces)
        }

        let sameDay = loans.filter { calendar.isDate($0.dueDate, inSameDayAs: first.dueDate) }
        let what: String = sameDay.count == 1 ? .local("« \(first.title) »") : .local("\(sameDay.count) documents")
        let others = loans.count - sameDay.count
        let more = others > 0 ? " " + String.local("Puis \(others) autres plus tard.") : ""
        let whenText = when(first.dueDate, now: now, calendar: calendar)
        return String.local("Vous devez rendre \(what) \(whenText).") + more
    }

    /// "aujourd'hui", "demain", "dans 3 jours, le jeudi 5 novembre"…
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let full = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch days {
        case 0: return .local("aujourd'hui")
        case 1: return .local("demain, le \(full)")
        default: return .local("dans \(days) jours, le \(full)")
        }
    }

    private static func nextAfter(_ late: [Loan], in loans: [Loan], now: Date, calendar: Calendar) -> String {
        let lateIDs = Set(late.map(\.id))
        guard let next = loans.first(where: { !lateIDs.contains($0.id) }) else { return "" }
        let whenText = when(next.dueDate, now: now, calendar: calendar)
        return .local("Prochain retour : « \(next.title) », \(whenText).")
    }
}
