import DesignSystem
import MediathequeCore
import SwiftUI

/// Onglet Recherche. Placé dans un `Tab(role: .search)`, son champ s'affiche en bas
/// sur iPhone, comme dans iOS 26.
public struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var path: [Notice] = []
    /// iPad : notice affichée dans la colonne de droite.
    @State private var selected: Notice?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let focusRequest: Int

    /// `focusRequest` : chaque changement donne le focus au champ de recherche (⌘F).
    public init(focusRequest: Int = 0) {
        self.focusRequest = focusRequest
    }

    /// Avec un view model détenu par l'appelant, qui survit à la disparition de la vue (iPad).
    public init(viewModel: SearchViewModel, focusRequest: Int = 0) {
        _viewModel = State(initialValue: viewModel)
        self.focusRequest = focusRequest
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad : résultats et fiche côte à côte. Pas de NavigationSplitView ici :
                // la racine de l'app en est déjà un (barre latérale).
                NavigationStack {
                    HStack(spacing: 0) {
                        searchColumn
                            .frame(width: 420)
                        Divider()
                        detailColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                NavigationStack(path: $path) {
                    searchColumn
                        .navigationDestination(for: Notice.self) { document in
                            DocumentDetailView(document: document)
                        }
                }
            }
        }
        .onChange(of: focusRequest) { isSearchFocused = true }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let selected {
            DocumentDetailView(document: selected).id(selected.id)
        } else {
            ContentUnavailableView(
                "Choisissez un document",
                systemImage: "books.vertical",
                description: Text("Sa fiche s'affiche ici, avec les exemplaires disponibles dans les 3 médiathèques.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceGrouped)
        }
    }

    @ViewBuilder
    private var searchColumn: some View {
        if sizeClass == .regular {
            // iPad : le champ est en haut de la colonne des résultats, pas dans la barre de navigation.
            VStack(spacing: 0) {
                ColumnSearchField(text: $viewModel.text, isFocused: $isSearchFocused) { viewModel.submit() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                content
            }
            .modifier(SearchColumnChrome(viewModel: viewModel))
        } else {
            content
                .modifier(SearchColumnChrome(viewModel: viewModel))
                .searchable(
                    text: $viewModel.text,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Titre, auteur, sujet, ISBN"
                )
                .searchFocused($isSearchFocused)
                .onSubmit(of: .search) { viewModel.submit() }
        }
    }

    /// Lien vers la fiche : pile de navigation sur iPhone, colonne de droite sur iPad.
    @ViewBuilder
    private func resultLink(_ document: Notice) -> some View {
        let row = SearchResultRow(document: document, availability: viewModel.availability[document.id])
        Group {
            if sizeClass == .regular {
                Button { selected = document } label: {
                    row.background(selected?.id == document.id ? Color.soft(.brandViolet) : .clear)
                }
                .accessibilityAddTraits(selected?.id == document.id ? .isSelected : [])
            } else {
                NavigationLink(value: document) { row }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            if let permalink = document.permalink {
                ShareLink("Partager", item: permalink, subject: Text(document.title))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.showsLanding {
            SearchLandingView(viewModel: viewModel)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScopeBar(viewModel: viewModel)
                    results
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 18) { ForEach(0..<5, id: \.self) { _ in SkeletonRow() } }
                .cardStyle()
        case let .failed(error):
            EmptyStateView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: error == .offline ? "Pas de connexion" : "Le site de la médiathèque ne répond pas",
                message: "Vérifiez votre connexion, puis réessayez.",
                primary: ("Réessayer", { viewModel.submit() })
            )
        case let .loaded(documents) where documents.isEmpty:
            EmptyStateView(
                systemImage: "text.magnifyingglass",
                title: "Aucun résultat",
                message: "Vérifiez l'orthographe, essayez moins de mots ou cherchez dans les 3 médiathèques.",
                primary: viewModel.hasActiveFilters ? ("Retirer les filtres", { viewModel.clearFilters() }) : nil
            )
        case let .loaded(documents):
            Text("\(viewModel.total) résultat\(viewModel.total > 1 ? "s" : "")")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
            LazyVStack(spacing: 0) {
                ForEach(documents) { document in
                    resultLink(document)
                        .onAppear { viewModel.rowAppeared(document) }
                    if document.id != documents.last?.id { Divider().padding(.leading, 76) }
                }
                if viewModel.isLoadingMore {
                    ProgressView().padding()
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

/// Titre, retour d'exploration et suivi de la saisie, communs à l'iPhone et à l'iPad.
private struct SearchColumnChrome: ViewModifier {
    let viewModel: SearchViewModel

    func body(content: Content) -> some View {
        content
            .background(Color.surfaceGrouped)
            .navigationTitle(viewModel.browsingTitle ?? "Recherche")
            .toolbar {
                if viewModel.browsingTitle != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retour", systemImage: "chevron.left") { viewModel.cancelBrowsing() }
                    }
                }
            }
            .onChange(of: viewModel.text) { viewModel.textDidChange() }
    }
}

/// Champ de recherche posé dans la colonne des résultats (iPad).
struct ColumnSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
            TextField("Titre, auteur, sujet, ISBN", text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(submit)
            if !text.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.inkSecondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Filtres

struct ScopeBar: View {
    let viewModel: SearchViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    Chip(scope.title, isSelected: viewModel.scope == scope) { viewModel.select(scope: scope) }
                }
                Menu {
                    Button("Toutes les médiathèques") { viewModel.select(library: nil) }
                    ForEach(Library.allCases) { library in
                        Button(library.name) { viewModel.select(library: library) }
                    }
                } label: {
                    Label(viewModel.library?.shortName ?? "Médiathèque", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(viewModel.library == nil ? .medium : .bold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(viewModel.library == nil ? Color.surfaceCard : Color.brandViolet, in: Capsule())
                        .foregroundStyle(viewModel.library == nil ? Color.ink : .white)
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .bold : .medium))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? Color.brandViolet : Color.surfaceCard, in: Capsule())
                .foregroundStyle(isSelected ? .white : Color.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Ligne de résultat

struct SearchResultRow: View {
    let document: Notice
    let availability: Availability?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(url: document.coverURL, title: document.title, seed: document.id)
                .frame(width: 52, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title).font(.headline).foregroundStyle(Color.ink).lineLimit(2)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(1)
                availabilityView
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        ([document.authors.first, document.kind.label, document.year].compactMap { $0 }).joined(separator: " · ")
    }

    @ViewBuilder
    private var availabilityView: some View {
        if document.kind.isDigital {
            StatusPill("En ligne · inclus dans l'abonnement", style: .accent)
        } else if let availability {
            HStack(spacing: 6) {
                StatusPill(availability.label, style: availability.isAvailable ? .success : .neutral)
                if !document.libraries.isEmpty {
                    Text(document.libraries.map(\.shortName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
            }
        } else {
            Text(document.libraries.map(\.shortName).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
        }
    }
}

// MARK: - Avant de chercher

struct SearchLandingView: View {
    let viewModel: SearchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Récentes") {
                            Button("Effacer") { viewModel.clearRecentSearches() }.font(.subheadline.weight(.semibold))
                        }
                        VStack(spacing: 0) {
                            ForEach(viewModel.recentSearches, id: \.self) { search in
                                Button { viewModel.search(recent: search) } label: {
                                    Label(search, systemImage: "clock.arrow.circlepath")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .frame(height: 48)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if search != viewModel.recentSearches.last { Divider().padding(.leading, 44) }
                            }
                        }
                        .cardStyle(padding: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Explorer")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(ExploreShortcut.all.enumerated()), id: \.element.id) { index, shortcut in
                            ExploreTile(shortcut: shortcut, index: index) { viewModel.open(shortcut) }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

struct ExploreTile: View {
    let shortcut: ExploreShortcut
    let index: Int
    let action: () -> Void

    var body: some View {
        let colors = BrandArtwork.colors(for: index)
        Button(action: action) {
            VStack(alignment: .leading) {
                Image(systemName: shortcut.systemImage).font(.title2)
                Spacer()
                Text(shortcut.title).font(.headline)
            }
            .foregroundStyle(BrandArtwork.foreground(for: index))
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension FeedbackEvent {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .error: .error
        case .selection: .selection
        case .lightImpact: .impact(weight: .light)
        }
    }
}

#Preview {
    TabView {
        Tab(role: .search) { SearchView() }
    }
    .environment(SessionStore())
}
