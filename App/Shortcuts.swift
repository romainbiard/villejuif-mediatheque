import AppIntents
import MediathequeCore
import SwiftUI

// MARK: - Routage

/// Ce qu'un raccourci demande à l'app une fois au premier plan ; `RootTabView` le consomme.
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

/// « Quand dois-je rendre mes livres ? » : répond sans ouvrir l'app, à partir du snapshot de l'appareil.
struct NextReturnsIntent: AppIntent {
    static let title: LocalizedStringResource = "Prochains retours"
    static let description = IntentDescription("Dit quand rendre vos prochains documents, d'après la dernière synchronisation.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let now = Date.now
        let snapshot = SnapshotClient.liveValue.load()
        let sentence = ReturnsSummary.sentence(for: snapshot, now: now, calendar: .paris)
        return .result(dialog: IntentDialog(stringLiteral: sentence)) {
            NextReturnsSnippet(snapshot: snapshot, now: now)
        }
    }
}

/// Ouvre la carte d'abonné en grand, pour le comptoir.
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

/// Cherche dans le catalogue des 3 médiathèques.
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

/// Ouvre l'agenda des animations.
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

// MARK: - Raccourcis (Siri, Spotlight, bouton Action)

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

// MARK: - Aperçu sous la réponse de Siri

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
                    Text("Synchronisé le \(updatedAt.formatted(.dateTime.day().month().hour().minute()))")
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
