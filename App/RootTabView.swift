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

    /// Ordre de la barre d'onglets et des raccourcis ⌘1…⌘5.
    static let main: [AppTab] = [.account, .agenda, .digital, .info, .search]

    var title: String {
        switch self {
        case .account: "Compte"
        case .agenda: "Agenda"
        case .digital: "Numérique"
        case .info: "Infos"
        case .search: "Recherche"
        case let .accountSection(section): section.title
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .agenda: "calendar"
        case .digital: "play.rectangle.on.rectangle"
        case .info: "mappin.and.ellipse"
        case .search: "magnifyingglass"
        case let .accountSection(section): section.systemImage
        }
    }
}

/// iPhone (et fenêtre étroite sur iPad) : barre d'onglets iOS 26 en Liquid Glass, Recherche en onglet
/// de rôle `.search`. iPad : barre latérale toujours ouverte, où les sections de Mon compte
/// ont leurs propres entrées.
struct RootTabView: View {
    @State private var selection: AppTab = .account
    @State private var searchFocusRequest = 0
    /// Demandes des raccourcis (App Intents), relayées aux écrans concernés.
    @State private var cardRequest = false
    @State private var searchQueryRequest: String?
    @State private var intentRouter = AppIntentRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SessionStore.self) private var session
    @State private var windowWidth: CGFloat = .infinity

    /// La barre latérale prend ~320 pt : en dessous de cette largeur de fenêtre (iPhone Duo déplié
    /// tenu à la verticale, iPad en Split View étroit), la barre d'onglets laisse plus de place au contenu.
    static let sidebarMinWindowWidth: CGFloat = 800

    private var usesSidebar: Bool { sizeClass == .regular && windowWidth >= Self.sidebarMinWindowWidth }

    var body: some View {
        Group {
            if usesSidebar {
                SidebarRootView(
                    selection: $selection,
                    searchFocusRequest: searchFocusRequest,
                    cardRequest: $cardRequest,
                    searchQueryRequest: $searchQueryRequest
                )
            } else {
                tabs
            }
        }
        .tint(.brandViolet)
        .measuringWidth($windowWidth)
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
        .onChange(of: intentRouter.pending, initial: true) { handleIntentRequest() }
        .onChange(of: usesSidebar) {
            // Les sections de Mon compte n'existent pas dans la barre d'onglets.
            if !usesSidebar, case .accountSection = selection { selection = .account }
        }
    }

    private func handleIntentRequest() {
        guard let request = intentRouter.pending else { return }
        intentRouter.pending = nil
        switch request {
        case .libraryCard:
            selection = .account
            cardRequest = true
        case let .search(query):
            selection = .search
            searchQueryRequest = query
        case let .tab(tab):
            selection = tab
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(AppTab.account.title, systemImage: AppTab.account.systemImage, value: .account) {
                AccountView(cardRequest: $cardRequest)
            }
            Tab(AppTab.agenda.title, systemImage: AppTab.agenda.systemImage, value: .agenda) {
                AgendaView()
            }
            Tab(AppTab.digital.title, systemImage: AppTab.digital.systemImage, value: .digital) {
                DigitalView()
            }
            Tab(AppTab.info.title, systemImage: AppTab.info.systemImage, value: .info) {
                InfoView()
            }
            Tab(value: .search, role: .search) {
                SearchView(focusRequest: searchFocusRequest, queryRequest: $searchQueryRequest)
            }
        }
    }
}

// MARK: - iPad

/// Barre latérale permanente : `TabView(.sidebarAdaptable)` laisse toujours la replier
/// en barre d'onglets en haut, peu pratique ; un `NavigationSplitView` la garde ouverte.
struct SidebarRootView: View {
    @Binding var selection: AppTab
    let searchFocusRequest: Int
    @Binding var cardRequest: Bool
    @Binding var searchQueryRequest: String?
    @Environment(SessionStore.self) private var session
    /// Détenu ici pour garder la requête et les résultats quand on change d'écran.
    @State private var searchModel = SearchViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding<AppTab?>(get: { selection }, set: { if let tab = $0 { selection = tab } })) {
                ForEach(AppTab.main, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
                if let patron = session.patron {
                    Section("Mon compte") {
                        ForEach(AccountSection.allCases) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .badge(badge(for: section, patron: patron))
                                .tag(AppTab.accountSection(section))
                        }
                    }
                }
            }
            .navigationTitle("Ma médiathèque")
            .navigationSplitViewColumnWidth(280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // Un seul écran à la fois : des écrans superposés se partageraient la barre de
            // navigation de la colonne. La recherche garde son état grâce à `searchModel`.
            screen(for: selection).id(selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .account: AccountView(cardRequest: $cardRequest)
        case .agenda: AgendaView()
        case .digital: DigitalView()
        case .info: InfoView()
        case .search: SearchView(viewModel: searchModel, focusRequest: searchFocusRequest, queryRequest: $searchQueryRequest)
        case let .accountSection(section): AccountSectionView(section)
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
                Button(tab.title) { navigation?.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(navigation == nil)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(SessionStore())
}
