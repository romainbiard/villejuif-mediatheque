// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Description of a request to the portal. Bokeh routes are path
/// segments (`/cle/valeur`), hence building them with `pathSegments`.
public struct Endpoint: Sendable, Equatable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }

    public var method: Method
    public var pathSegments: [String]
    public var query: [FormField]
    public var form: [FormField]
    /// Adds `X-Requested-With: XMLHttpRequest`: Bokeh popups then return JSON.
    public var isAjax: Bool

    public init(
        method: Method = .get,
        pathSegments: [String],
        query: [FormField] = [],
        form: [FormField] = [],
        isAjax: Bool = false
    ) {
        self.method = method
        self.pathSegments = pathSegments
        self.query = query
        self.form = form
        self.isAjax = isAjax
    }

    public struct FormField: Sendable, Equatable {
        public let name: String
        public let value: String
        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// Unique key for a GET request (path and parameters), for caches.
    public var cacheKey: String {
        ([encodedPath] + query.map { "\($0.name)=\($0.value)" }).joined(separator: "&")
    }

    /// Percent-encoded path, segment by segment (spaces become `%20`).
    var encodedPath: String {
        "/" + pathSegments
            .map { $0.addingPercentEncoding(withAllowedCharacters: .bokehPathSegment) ?? $0 }
            .joined(separator: "/")
    }

    func url(relativeTo baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = encodedPath
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.name, value: $0.value) }
        }
        return components.url!
    }
}

extension CharacterSet {
    /// Characters allowed in a segment: we encode `/`, `*` and spaces.
    static let bokehPathSegment: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/*")
        return set
    }()
}

// MARK: - Catalog

extension Endpoint {
    /// Simple search in JSON format. Facets are combined (AND) via `facettes/T1-Y2`.
    /// `*` browses the whole catalog; `sort: "date_creation desc"` gives new arrivals.
    public static func search(_ query: String, facets: [String] = [], sort: String = "*", page: Int = 1) -> Endpoint {
        var segments = ["recherche", "simple", "expressionRecherche", query.isEmpty ? "*" : query, "tri", sort]
        if !facets.isEmpty {
            segments += ["facettes", facets.joined(separator: "-")]
        }
        segments += ["format", "json"]
        if page > 1 { segments += ["page", String(page)] }
        return Endpoint(pathSegments: segments)
    }

    /// Real-time availability badge (HTML).
    public static func availability(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["noticeajax", "availability", "id", String(recordID)])
    }

    /// Real-time copies (HTML): status, call number, due date, holds.
    public static func copies(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["noticeajax", "exemplaires", "id", String(recordID)])
    }

    /// Search autocomplete.
    public static func suggest(_ prefix: String) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "suggestajax"], query: [FormField("startsWith", prefix)])
    }
}

// MARK: - Agenda and practical info

extension Endpoint {
    /// Agenda page (server-rendered, unlike `/cms/calendar/...` which loads via AJAX).
    /// The filters are the same segments as on the site.
    public static func calendar(placeID: Int? = nil, typeID: Int? = nil, audienceID: Int? = nil) -> Endpoint {
        var segments = ["accueil", "agenda"]
        if let placeID { segments += ["place", String(placeID)] }
        if let typeID { segments += ["custom_field_2", String(typeID)] }
        if let audienceID { segments += ["custom_field_3", String(audienceID)] }
        return Endpoint(pathSegments: segments)
    }

    public static func eventICal(articleID: Int) -> Endpoint {
        Endpoint(pathSegments: ["cms", "ical", "id_article", String(articleID)])
    }

    public static let practicalInfo = Endpoint(pathSegments: ["accueil", "infos_pratiques"])
}

// MARK: - Authentication

extension Endpoint {
    public static let loginPage = Endpoint(pathSegments: ["auth", "login"])

    public static func login(cardNumber: String, password: String, csrfToken: String) -> Endpoint {
        Endpoint(method: .post, pathSegments: ["auth", "login"], form: [
            FormField("username", cardNumber),
            FormField("password", password),
            FormField("login", "Se connecter"),
            FormField("csrftoken", csrfToken)
        ])
    }

    public static let lostPasswordPage = Endpoint(pathSegments: ["auth", "lostpass"])

    /// `website` is an anti-spam honeypot field that must stay empty; the form
    /// must be submitted at least `minimum_time` seconds after it is displayed.
    public static func lostPassword(cardNumber: String, csrfToken: String) -> Endpoint {
        Endpoint(method: .post, pathSegments: ["auth", "lostpass"], form: [
            FormField("lost_username", cardNumber),
            FormField("website", ""),
            FormField("minimum_time", "2"),
            FormField("csrftoken", csrfToken)
        ])
    }

    public static let logout = Endpoint(pathSegments: ["auth", "logout"])
}

// MARK: - Patron account (JSON, with the session cookie)

extension Endpoint {
    public static let account = Endpoint(pathSegments: ["api", "user", "account"])
    public static let loans = Endpoint(pathSegments: ["api", "user", "loans"])
    public static let holds = Endpoint(pathSegments: ["api", "user", "holds"])

    /// Renews one or more loans (identifiers separated by `;`).
    public static func renewLoans(patronID: String, loanIDs: [String]) -> Endpoint {
        Endpoint(pathSegments: [
            "abonne", "prolongerPret", "id_profil", "1", "id", patronID,
            "id_pret", loanIDs.joined(separator: ";")
        ])
    }

    public static func cancelHold(holdID: String) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "reservations", "id_delete", holdID])
    }

    /// HTML holds page: the only source for the queue position.
    public static func holdsPage(patronID: String) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "reservations", "id_profil", "1", "id", patronID])
    }

    public static func bookmarkLibrary(libraryID: Int) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "add-library-to-bookmarks", "library_id", String(libraryID)])
    }
}

// MARK: - Holds (AJAX popups)

extension Endpoint {
    public static func holdOptions(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "reserver", "record_id", String(recordID), "render", "popup"], isAjax: true)
    }

    /// `path` is the `reservation-pickup-ajax/...` link read from `holdOptions`.
    public static func pickupForm(path: String) -> Endpoint {
        Endpoint(pathSegments: path.split(separator: "/").map(String.init), isAjax: true)
    }

    public static func submitPickup(path: String, pickupLibraryCode: String) -> Endpoint {
        Endpoint(
            method: .post,
            pathSegments: path.split(separator: "/").map(String.init),
            form: [FormField("code_annexe", pickupLibraryCode)],
            isAjax: true
        )
    }
}

// MARK: - Médiathèque Numérique

extension Endpoint {
    /// Tiny `<script>document.location.href="…"</script>` page that carries the SSO URL.
    public static func digitalModule(_ slug: String) -> Endpoint {
        Endpoint(pathSegments: ["modules", slug])
    }
}

// MARK: - Patron space (HTML pages and forms, checked on 31/10/2026)

extension Endpoint {
    /// Page of an account section: `/abonne/{page}/id_profil/1/id/{idAbonné}`.
    public static func patronPage(_ page: String, patronID: String) -> Endpoint {
        Endpoint(pathSegments: ["abonne", page, "id_profil", "1", "id", patronID])
    }

    /// Form of an account section, without a CSRF token.
    public static func patronForm(_ page: String, patronID: String, fields: [FormField]) -> Endpoint {
        Endpoint(method: .post, pathSegments: ["abonne", page, "id_profil", "1", "id", patronID], form: fields)
    }

    /// Contents of a selection: it's a JSON search on the basket.
    public static func selectionRecords(basketID: Int, page: Int = 1) -> Endpoint {
        var segments = ["recherche", "simple", "id_panier", String(basketID), "format", "json"]
        if page > 1 { segments += ["page", String(page)] }
        return Endpoint(pathSegments: segments)
    }

    /// Record page by its identifier alone. Signed in, it shows which default selections hold the record.
    public static func noticePage(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "viewnotice", "id", String(recordID)])
    }

    /// Adds a record to one of the site's default selections ("Mes préférés", "Déjà lu", "À lire") or removes it.
    /// `image` and `revertImage` are the site's own icons for the toggle; it answers with the new link (JSON).
    /// The label goes as the site writes it, spaces as `+` (`Mes+préférés`).
    public static func toggleDefaultSelection(label: String, image: String, revertImage: String, recordID: Int, adding: Bool) -> Endpoint {
        let selection = ["selection_label", label.replacingOccurrences(of: " ", with: "+"), "image", image, "revert-image", revertImage]
        return adding
            ? Endpoint(pathSegments: ["abonne", "ajouter-le-document-a-la-selection"] + selection + ["record_id", String(recordID)], isAjax: true)
            : Endpoint(pathSegments: ["abonne", "supprimer-de-la-selection"] + selection + ["record_id", String(recordID), "ajax", "true"], isAjax: true)
    }

    public static func removeFromSelection(patronID: String, selectionID: Int, recordID: Int) -> Endpoint {
        Endpoint(pathSegments: [
            "abonne", "supprimer-de-la-selection", "id_profil", "1", "id", patronID,
            "selection_id", String(selectionID), "record_id", String(recordID), "delete", "1"
        ])
    }

    /// Review of a borrowed document: rating from 1 to 5, title and text.
    public static func submitReview(recordID: Int, recordKey: String, rating: Int, title: String, text: String) -> Endpoint {
        Endpoint(
            method: .post,
            pathSegments: ["abonne", "ajax-review", "record_id", String(recordID), "record_key", recordKey],
            form: [FormField("note", String(rating)), FormField("entete", title), FormField("avis", text)]
        )
    }

    public static func removeLibraryBookmark(libraryID: Int) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "remove-library-from-bookmarks", "library_id", String(libraryID)])
    }

    public static func subscribeNewsletter(id: Int) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "subscribe-newsletter", "id", String(id)])
    }
}
