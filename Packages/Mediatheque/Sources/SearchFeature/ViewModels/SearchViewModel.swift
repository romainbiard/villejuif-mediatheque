import Dependencies
import Foundation
import MediathequeCore
import Observation

/// Filtres rapides de la recherche. Les facettes Bokeh se combinent en ET :
/// un seul type à la fois, d'où une liste exclusive plutôt que des cases à cocher.
public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, books, dvd, cd, audiobooks, ebooks, onlineFilms

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "Tout"
        case .books: "Livres"
        case .dvd: "DVD"
        case .cd: "CD"
        case .audiobooks: "Livres audio"
        case .ebooks: "E-books"
        case .onlineFilms: "Films en ligne"
        }
    }

    var kinds: [DocumentKind] {
        switch self {
        case .all: []
        case .books: [.book]
        case .dvd: [.dvd]
        case .cd: [.cd]
        case .audiobooks: [.audiobook]
        case .ebooks: [DocumentKind(code: "Numilog", label: "Livres numériques")]
        case .onlineFilms: [DocumentKind(code: "ArteVod", label: "Cinéma en ligne")]
        }
    }
}

/// Tuile « Explorer » de l'écran de recherche vide : une recherche préremplie.
public struct ExploreShortcut: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let scope: SearchScope
    public let sort: SearchQuery.Sort

    public static let all: [ExploreShortcut] = [
        ExploreShortcut(id: "new", title: "Nouveautés", systemImage: "sparkles", scope: .books, sort: .newest),
        ExploreShortcut(id: "films", title: "Films", systemImage: "film", scope: .dvd, sort: .newest),
        ExploreShortcut(id: "music", title: "Musique", systemImage: "music.note", scope: .cd, sort: .newest),
        ExploreShortcut(id: "ebooks", title: "E-books", systemImage: "ipad", scope: .ebooks, sort: .newest),
        ExploreShortcut(id: "audio", title: "Livres audio", systemImage: "headphones", scope: .audiobooks, sort: .newest),
        ExploreShortcut(id: "online", title: "Films en ligne", systemImage: "play.tv", scope: .onlineFilms, sort: .newest),
    ]
}

@MainActor
@Observable
public final class SearchViewModel {
    public var text = ""
    public private(set) var scope: SearchScope = .all
    public private(set) var library: Library?
    public private(set) var sort: SearchQuery.Sort = .relevance
    public private(set) var state: LoadState<[Notice]> = .idle
    public private(set) var total = 0
    public private(set) var isLoadingMore = false
    public private(set) var availability: [Notice.ID: Availability] = [:]
    public private(set) var recentSearches: [String] = []
    public private(set) var feedback: FeedbackEvent?

    /// Titre de l'écran « exploration » quand on vient d'une tuile, sans texte saisi.
    public private(set) var browsingTitle: String?

    @ObservationIgnored @Dependency(\.catalogClient) private var catalog
    @ObservationIgnored @Dependency(\.recentSearches) private var recents
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    @ObservationIgnored private var page = 1
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var availabilityRequests: Set<Notice.ID> = []

    static let debounce: Duration = .milliseconds(350)

    public init() {
        recentSearches = recents.load()
    }

    /// Vrai quand on montre les recherches récentes et les tuiles plutôt que des résultats.
    public var showsLanding: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty && browsingTitle == nil
    }

    // MARK: Intentions

    /// Saisie en cours : on attend une pause avant de lancer la recherche.
    public func textDidChange() {
        browsingTitle = nil
        sort = .relevance
        scheduleSearch(after: Self.debounce)
    }

    /// Validation au clavier : recherche immédiate et mémorisation.
    public func submit() {
        remember(text)
        scheduleSearch(after: nil)
    }

    public func select(scope: SearchScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        feedback = .selection
        scheduleSearch(after: nil)
    }

    public func select(library: Library?) {
        guard library != self.library else { return }
        self.library = library
        feedback = .selection
        scheduleSearch(after: nil)
    }

    public func open(_ shortcut: ExploreShortcut) {
        text = ""
        browsingTitle = shortcut.title
        scope = shortcut.scope
        sort = shortcut.sort
        scheduleSearch(after: nil)
    }

    public func search(recent: String) {
        text = recent
        submit()
    }

    public func clearRecentSearches() {
        recentSearches = []
        recents.save([])
    }

    public func clearFilters() {
        scope = .all
        library = nil
        scheduleSearch(after: nil)
    }

    public func cancelBrowsing() {
        browsingTitle = nil
        sort = .relevance
        state = .idle
    }

    /// À appeler quand une ligne apparaît : charge la page suivante près de la fin.
    public func rowAppeared(_ document: Notice) {
        loadAvailabilityIfNeeded(for: document)
        guard let documents = state.value, !isLoadingMore,
              documents.suffix(3).contains(where: { $0.id == document.id }),
              documents.count < total
        else { return }
        Task { await loadNextPage() }
    }

    public var hasActiveFilters: Bool { scope != .all || library != nil }

    // MARK: Chargement

    private var query: SearchQuery {
        SearchQuery(
            text: text.trimmingCharacters(in: .whitespaces),
            kinds: scope.kinds,
            libraries: library.map { [$0] } ?? [],
            sort: sort,
            page: page
        )
    }

    private func scheduleSearch(after delay: Duration?) {
        searchTask?.cancel()
        guard !showsLanding else {
            state = .idle
            return
        }
        searchTask = Task {
            if let delay {
                do { try await clock.sleep(for: delay) } catch { return }
            }
            await runSearch()
        }
    }

    func runSearch() async {
        page = 1
        state = .loading
        availability = [:]
        availabilityRequests = []
        do {
            let result = try await catalog.search(query)
            guard !Task.isCancelled else { return }
            total = result.total
            state = .loaded(result.documents)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(LoadError(error))
        }
    }

    func loadNextPage() async {
        guard let documents = state.value else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        do {
            let result = try await catalog.search(query)
            let known = Set(documents.map(\.id))
            state = .loaded(documents + result.documents.filter { !known.contains($0.id) })
        } catch {
            page -= 1
        }
    }

    private func loadAvailabilityIfNeeded(for document: Notice) {
        // Les ressources en ligne n'ont pas d'exemplaire physique.
        guard !document.kind.isDigital, availabilityRequests.insert(document.id).inserted else { return }
        Task {
            if let result = try? await catalog.availability(document.id) {
                availability[document.id] = result
            }
        }
    }

    private func remember(_ search: String) {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recentSearches = Array(([trimmed] + recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }).prefix(8))
        recents.save(recentSearches)
    }
}
