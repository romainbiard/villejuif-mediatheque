// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

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
    /// A Mon compte section, shown only in the iPad sidebar.
    case accountSection(AccountSection)

    /// Order of the tab bar and of the ⌘1…⌘5 shortcuts.
    static let main: [AppTab] = [.account, .agenda, .digital, .info, .search]

    var title: String {
        switch self {
        case .account: String(localized: "Compte", comment: "Tab title")
        case .agenda: String(localized: "Agenda", comment: "Tab title: library events")
        case .digital: String(localized: "Numérique", comment: "Tab title: digital library")
        case .info: String(localized: "Infos", comment: "Tab title: practical information")
        case .search: String(localized: "Recherche", comment: "Tab title: catalog search")
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

/// iPhone (and narrow window on iPad): iOS 26 Liquid Glass tab bar, with Search as a tab
/// with the `.search` role. iPad: an always-open sidebar, where the Mon compte sections
/// have their own entries.
struct RootTabView: View {
    @State private var selection: AppTab = .account
    @State private var searchFocusRequest = 0
    /// Shortcut (App Intents) requests, relayed to the relevant screens.
    @State private var cardRequest = false
    @State private var searchQueryRequest: String?
    @State private var intentRouter = AppIntentRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SessionStore.self) private var session
    @State private var windowWidth: CGFloat = .infinity

    /// The sidebar takes ~320 pt: below this window width (iPhone Duo unfolded
    /// held upright, narrow iPad Split View), the tab bar leaves more room for the content.
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
            // The Mon compte sections don't exist in the tab bar.
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

/// Permanent sidebar: `TabView(.sidebarAdaptable)` always lets the user collapse it
/// into a tab bar at the top, which is impractical; a `NavigationSplitView` keeps it open.
struct SidebarRootView: View {
    @Binding var selection: AppTab
    let searchFocusRequest: Int
    @Binding var cardRequest: Bool
    @Binding var searchQueryRequest: String?
    @Environment(SessionStore.self) private var session
    /// Owned here to keep the query and results when switching screens.
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
            // One screen at a time: stacked screens would share the column's navigation
            // bar. Search keeps its state thanks to `searchModel`.
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

    /// Badges: overdue loans, holds ready for pickup.
    private func badge(for section: AccountSection, patron: Patron) -> Int {
        switch section {
        case .loans: patron.counters.lateLoans
        case .holds: patron.counters.waitingToBePulled
        default: 0
        }
    }
}

// MARK: - Keyboard shortcuts (iPad)

struct AppNavigation {
    let select: (AppTab) -> Void
    let focusSearch: () -> Void
}

extension FocusedValues {
    @Entry var appNavigation: AppNavigation?
}

/// "Aller à" menu in the iPad menu bar: ⌘1…⌘5 and ⌘F.
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
