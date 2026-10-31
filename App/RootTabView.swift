import AccountFeature
import AgendaFeature
import DesignSystem
import DigitalFeature
import InfoFeature
import MediathequeCore
import SearchFeature
import SwiftUI

enum AppTab: Hashable {
    case account, agenda, digital, info, search
    /// Une section de Mon compte, présente seulement dans la barre latérale de l'iPad.
    case accountSection(AccountSection)

    /// Ordre des raccourcis ⌘1…⌘5.
    static let main: [AppTab] = [.account, .agenda, .digital, .info, .search]
}

/// Barre d'onglets iOS 26 : Liquid Glass flottante, Recherche en onglet de rôle `.search`
/// (champ en bas sur iPhone), et barre latérale adaptable sur iPad, où les sections
/// de Mon compte ont leurs propres entrées.
struct RootTabView: View {
    @State private var selection: AppTab = .account
    @State private var searchFocusRequest = 0
    @AppStorage("sidebarCustomization") private var customization: TabViewCustomization
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView(selection: $selection) {
            Tab("Compte", systemImage: "person.crop.circle", value: .account) {
                AccountView()
            }
            .customizationID("tab.account")
            Tab("Agenda", systemImage: "calendar", value: .agenda) {
                AgendaView()
            }
            .customizationID("tab.agenda")
            Tab("Numérique", systemImage: "play.rectangle.on.rectangle", value: .digital) {
                DigitalView()
            }
            .customizationID("tab.digital")
            Tab("Infos", systemImage: "mappin.and.ellipse", value: .info) {
                InfoView()
            }
            .customizationID("tab.info")
            Tab(value: .search, role: .search) {
                SearchView(focusRequest: searchFocusRequest)
            }
            .customizationID("tab.search")

            if let patron = session.patron {
                TabSection("Mon compte") {
                    ForEach(AccountSection.allCases) { section in
                        Tab(section.title, systemImage: section.systemImage, value: AppTab.accountSection(section)) {
                            AccountSectionView(section)
                        }
                        .badge(badge(for: section, patron: patron))
                        .customizationID("account.\(section.rawValue)")
                        .defaultVisibility(.hidden, for: .tabBar)
                    }
                }
                .customizationID("section.account")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .tint(.brandViolet)
        .focusedSceneValue(\.appNavigation, AppNavigation(
            select: { selection = $0 },
            focusSearch: {
                selection = .search
                searchFocusRequest += 1
            }
        ))
        .onChange(of: session.patron == nil) { _, loggedOut in
            if loggedOut, case .accountSection = selection { selection = .account }
        }
    }

    /// Pastilles : prêts en retard, réservations à retirer.
    private func badge(for section: AccountSection, patron: Patron) -> Int {
        switch section {
        case .loans: patron.counters.lateLoans
        case .holds: patron.counters.waitingToBePulled
        default: 0
        }
    }
}

// MARK: - Raccourcis clavier (iPad)

struct AppNavigation {
    let select: (AppTab) -> Void
    let focusSearch: () -> Void
}

extension FocusedValues {
    @Entry var appNavigation: AppNavigation?
}

/// Menu « Aller à » de la barre des menus de l'iPad : ⌘1…⌘5 et ⌘F.
struct AppCommands: Commands {
    @FocusedValue(\.appNavigation) private var navigation

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Rechercher dans le catalogue") { navigation?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(navigation == nil)
        }
        CommandMenu("Aller à") {
            ForEach(Array(AppTab.main.enumerated()), id: \.offset) { index, tab in
                Button(Self.title(of: tab)) { navigation?.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(navigation == nil)
            }
        }
    }

    private static func title(of tab: AppTab) -> String {
        switch tab {
        case .account: "Mon compte"
        case .agenda: "Agenda"
        case .digital: "Médiathèque numérique"
        case .info: "Infos pratiques"
        case .search: "Recherche"
        case let .accountSection(section): section.title
        }
    }
}

#Preview {
    RootTabView()
        .environment(SessionStore())
}
