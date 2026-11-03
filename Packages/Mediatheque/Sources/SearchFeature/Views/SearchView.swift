// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import CoreUI
import DesignSystem
import MediathequeCore
import SwiftUI

/// Search tab. Placed in a `Tab(role: .search)`, its field shows at the bottom
/// on iPhone, as in iOS 26.
public struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var path: [Notice] = []
    /// iPad: record shown in the right column.
    @State private var selected: Notice?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var contentWidth: CGFloat = .infinity
    private let focusRequest: Int

    /// Results column (420 pt) and a detail view of at least 400 pt.
    static let columnsMinWidth: CGFloat = 820

    private var showsColumns: Bool { sizeClass == .regular && contentWidth >= Self.columnsMinWidth }
    /// Search requested from outside (Siri, Shortcuts): launched, then reset to `nil`.
    @Binding private var queryRequest: String?

    /// `focusRequest`: each change focuses the search field (⌘F).
    public init(focusRequest: Int = 0, queryRequest: Binding<String?> = .constant(nil)) {
        self.focusRequest = focusRequest
        _queryRequest = queryRequest
    }

    /// With a view model owned by the caller, which outlives the view (iPad).
    public init(viewModel: SearchViewModel, focusRequest: Int = 0, queryRequest: Binding<String?> = .constant(nil)) {
        _viewModel = State(initialValue: viewModel)
        self.focusRequest = focusRequest
        _queryRequest = queryRequest
    }

    public var body: some View {
        Group {
            if showsColumns {
                // iPad: results and detail side by side. No NavigationSplitView here:
                // the app's root is already one (sidebar).
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
        .measuringWidth($contentWidth)
        .onChange(of: focusRequest) { isSearchFocused = true }
        .onChange(of: queryRequest, initial: true) {
            guard let query = queryRequest else { return }
            path = []
            selected = nil
            viewModel.search(recent: query)
            queryRequest = nil
        }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let selected {
            DocumentDetailView(document: selected).id(selected.id)
        } else {
            ContentUnavailableView {
                Label(.local("Choisissez un document"), systemImage: "books.vertical")
            } description: {
                Text(.local("Sa fiche s'affiche ici, avec les exemplaires disponibles dans les 3 médiathèques."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfaceGrouped)
        }
    }

    @ViewBuilder
    private var searchColumn: some View {
        // Field in the column whenever the width is "regular": in the navigation bar,
        // iOS shrinks it to a floating button (iPhone Duo unfolded, iPad in a narrow window).
        if sizeClass == .regular {
            // iPad: the field is at the top of the results column, not in the navigation bar.
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
                    prompt: Text(.local("Titre, auteur, sujet, ISBN", comment: "Search field placeholder"))
                )
                .searchFocused($isSearchFocused)
                .onSubmit(of: .search) { viewModel.submit() }
        }
    }

    /// Link to the detail view: navigation stack on iPhone, right column on iPad.
    @ViewBuilder
    private func resultLink(_ document: Notice) -> some View {
        let row = SearchResultRow(document: document, availability: viewModel.availability[document.id])
        Group {
            if showsColumns {
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
                ShareLink(String.local("Partager"), item: permalink, subject: Text(document.title))
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
            EmptyStateView(error: error) { viewModel.submit() }
        case let .loaded(documents) where documents.isEmpty:
            EmptyStateView(
                systemImage: "text.magnifyingglass",
                title: String.local("Aucun résultat"),
                message: String.local("Vérifiez l'orthographe, essayez moins de mots ou cherchez dans les 3 médiathèques."),
                primary: viewModel.hasActiveFilters ? (String.local("Retirer les filtres"), { viewModel.clearFilters() }) : nil
            )
        case let .loaded(documents):
            Text(.local("\(viewModel.total) résultats"))
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

/// Title, back-from-exploration and input tracking, shared by iPhone and iPad.
private struct SearchColumnChrome: ViewModifier {
    let viewModel: SearchViewModel

    func body(content: Content) -> some View {
        content
            .background(Color.surfaceGrouped)
            .navigationTitle(viewModel.browsingTitle ?? String.local("Recherche", comment: "Screen title"))
            .toolbar {
                if viewModel.browsingTitle != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(.local("Retour"), systemImage: "chevron.left") { viewModel.cancelBrowsing() }
                    }
                }
            }
            .onChange(of: viewModel.text) { viewModel.textDidChange() }
            // The count only shows on screen: VoiceOver hears it once a new search has loaded.
            .onChange(of: viewModel.state.isLoading) { wasLoading, isLoading in
                guard wasLoading, !isLoading, let documents = viewModel.state.value else { return }
                let announcement = documents.isEmpty
                    ? String.local("Aucun résultat")
                    : String.local("\(viewModel.total) résultats")
                AccessibilityNotification.Announcement(announcement).post()
            }
    }
}

/// Search field placed in the results column (iPad).
struct ColumnSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
            TextField(String.local("Titre, auteur, sujet, ISBN", comment: "Search field placeholder"), text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(submit)
            if !text.isEmpty {
                Button(.local("Effacer", comment: "Clears the search field or the recent searches"), systemImage: "xmark.circle.fill") { text = "" }
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

// MARK: - Filters

struct ScopeBar: View {
    let viewModel: SearchViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    Chip(scope.title, isSelected: viewModel.scope == scope) { viewModel.select(scope: scope) }
                }
                Menu {
                    Button(.local("Toutes les médiathèques")) { viewModel.select(library: nil) }
                    ForEach(Library.allCases) { library in
                        Button(library.name) { viewModel.select(library: library) }
                    }
                } label: {
                    Label(
                        viewModel.library?.shortName ?? String.local("Médiathèque", comment: "Library filter menu, when no library is selected"),
                        systemImage: "mappin.and.ellipse"
                    )
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

// MARK: - Result row

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
        ([document.authors.first, document.kind.label, document.year].compactMap(\.self)).joined(separator: " · ")
    }

    @ViewBuilder
    private var availabilityView: some View {
        if document.kind.isDigital {
            StatusPill(String.local("En ligne · inclus dans l'abonnement"), style: .accent)
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

// MARK: - Before searching

struct SearchLandingView: View {
    let viewModel: SearchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(String.local("Récentes", comment: "Section: recent searches")) {
                            Button(.local("Effacer", comment: "Clears the search field or the recent searches")) { viewModel.clearRecentSearches() }
                                .font(.subheadline.weight(.semibold))
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
                    SectionHeader(String.local("Explorer", comment: "Section of search shortcut tiles"))
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
