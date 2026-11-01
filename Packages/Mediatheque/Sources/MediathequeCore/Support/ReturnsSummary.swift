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
            return "Connectez-vous dans l'app Ma médiathèque pour suivre vos prêts."
        }
        let loans = snapshot.upcomingLoans
        guard let first = loans.first else {
            return "Vous n'avez aucun prêt en cours."
        }

        let late = loans.filter { if case .late = $0.dueState(now: now, calendar: calendar) { true } else { false } }
        if !late.isEmpty {
            let titles = late.count == 1 ? "« \(late[0].title) » est" : "\(late.count) documents sont"
            return "\(titles) en retard. \(nextAfter(late, in: loans, now: now, calendar: calendar))"
                .trimmingCharacters(in: .whitespaces)
        }

        let sameDay = loans.filter { calendar.isDate($0.dueDate, inSameDayAs: first.dueDate) }
        let what = sameDay.count == 1 ? "« \(first.title) »" : "\(sameDay.count) documents"
        let more = loans.count > sameDay.count
            ? " Puis \(loans.count - sameDay.count) autre\(loans.count - sameDay.count > 1 ? "s" : "") plus tard."
            : ""
        return "Vous devez rendre \(what) \(when(first.dueDate, now: now, calendar: calendar)).\(more)"
    }

    /// "aujourd'hui", "demain", "dans 3 jours, le jeudi 5 novembre"…
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let french = Locale(identifier: "fr_FR")
        let full = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french))
        switch days {
        case 0: return "aujourd'hui"
        case 1: return "demain, le \(full)"
        default: return "dans \(days) jours, le \(full)"
        }
    }

    private static func nextAfter(_ late: [Loan], in loans: [Loan], now: Date, calendar: Calendar) -> String {
        let lateIDs = Set(late.map(\.id))
        guard let next = loans.first(where: { !lateIDs.contains($0.id) }) else { return "" }
        return "Prochain retour : « \(next.title) », \(when(next.dueDate, now: now, calendar: calendar))."
    }
}
