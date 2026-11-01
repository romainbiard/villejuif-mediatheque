// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import AppIntents
import MediathequeCore
import SwiftUI

// MARK: - Routing

/// What a shortcut asks of the app once it is in the foreground; `RootTabView` consumes it.
@MainActor
@Observable
final class AppIntentRouter {
    static let shared = AppIntentRouter()

    enum Request: Equatable {
        case libraryCard
        case search(String)
        case tab(AppTab)
    }

    var pending: Request?
}

// MARK: - Intents

/// "Quand dois-je rendre mes livres ?": answers without opening the app, from the on-device snapshot.
struct NextReturnsIntent: AppIntent {
    static let title: LocalizedStringResource = "Prochains retours"
    static let description = IntentDescription("Dit quand rendre vos prochains documents, d'après la dernière synchronisation.")
    /// Titles of what the patron borrows: never read out while the iPhone is locked.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let now = Date.now
        let snapshot = SnapshotClient.liveValue.load()
        let sentence = ReturnsSummary.sentence(for: snapshot, now: now, calendar: .paris)
        return .result(dialog: IntentDialog(stringLiteral: sentence)) {
            NextReturnsSnippet(snapshot: snapshot, now: now)
        }
    }
}

/// Opens the library card full screen, for the front desk.
struct ShowLibraryCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Montrer ma carte d'abonné"
    static let description = IntentDescription("Affiche votre carte avec son code-barres, luminosité au maximum.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.pending = .libraryCard
        return .result()
    }
}

/// Searches the catalog of the 3 libraries.
struct SearchCatalogIntent: AppIntent {
    static let title: LocalizedStringResource = "Chercher dans le catalogue"
    static let description = IntentDescription("Lance une recherche dans le catalogue des médiathèques de Villejuif.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Recherche", requestValueDialog: "Que cherchez-vous ?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Chercher \(\.$query) dans le catalogue")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.pending = .search(query)
        return .result()
    }
}

/// Opens the events calendar.
struct OpenAgendaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir l'agenda"
    static let description = IntentDescription("Affiche les prochaines animations des médiathèques.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.pending = .tab(.agenda)
        return .result()
    }
}

// MARK: - Shortcuts (Siri, Spotlight, Action button)

struct VillejuifShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextReturnsIntent(),
            phrases: [
                "Quand dois-je rendre mes livres dans \(.applicationName) ?",
                "Mes prochains retours \(.applicationName)",
                "Quels prêts rendre avec \(.applicationName) ?",
            ],
            shortTitle: "Prochains retours",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: ShowLibraryCardIntent(),
            phrases: [
                "Montre ma carte \(.applicationName)",
                "Ma carte d'abonné \(.applicationName)",
            ],
            shortTitle: "Ma carte",
            systemImageName: "barcode"
        )
        AppShortcut(
            intent: SearchCatalogIntent(),
            phrases: [
                "Chercher un livre dans \(.applicationName)",
                "Recherche dans \(.applicationName)",
            ],
            shortTitle: "Chercher",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenAgendaIntent(),
            phrases: [
                "Agenda \(.applicationName)",
                "Quelles animations dans \(.applicationName) ?",
            ],
            shortTitle: "Agenda",
            systemImageName: "calendar"
        )
    }
}

// MARK: - Preview below Siri's answer

struct NextReturnsSnippet: View {
    let snapshot: AccountSnapshot?
    let now: Date

    var body: some View {
        if let loans = snapshot?.upcomingLoans.prefix(3), !loans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(loans)) { loan in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loan.title).font(.headline).lineLimit(1)
                            Text(loan.library?.shortName ?? loan.libraryName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(loan.dueDate.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isLate(loan) ? Color.red : Color.primary)
                    }
                }
                if let updatedAt = snapshot?.updatedAt {
                    Text("Synchronisé le \(updatedAt.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "fr_FR"))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func isLate(_ loan: Loan) -> Bool {
        if case .late = loan.dueState(now: now, calendar: .paris) { true } else { false }
    }
}
