import Foundation

/// Description d'une requête vers le portail. Les routes Bokeh sont des segments
/// de chemin (`/cle/valeur`), d'où la construction par `pathSegments`.
public struct Endpoint: Sendable, Equatable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }

    public var method: Method
    public var pathSegments: [String]
    public var query: [FormField]
    public var form: [FormField]
    /// Ajoute `X-Requested-With: XMLHttpRequest` : les popups Bokeh renvoient alors du JSON.
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

    /// Chemin percent-encodé, segment par segment (les espaces deviennent `%20`).
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
    /// Caractères autorisés dans un segment : on encode `/`, `*` et les espaces.
    static let bokehPathSegment: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/*")
        return set
    }()
}

// MARK: - Catalogue

extension Endpoint {
    /// Recherche simple au format JSON. Les facettes sont combinées (ET) par `facettes/T1-Y2`.
    public static func search(_ query: String, facets: [String] = [], page: Int = 1) -> Endpoint {
        var segments = ["recherche", "simple", "expressionRecherche", query, "tri", "*"]
        if !facets.isEmpty {
            segments += ["facettes", facets.joined(separator: "-")]
        }
        segments += ["format", "json"]
        if page > 1 { segments += ["page", String(page)] }
        return Endpoint(pathSegments: segments)
    }

    public static func notice(key: String, id: Int) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "viewnotice", "clef", key, "id", String(id), "format", "json"])
    }

    /// Page HTML complète de la notice (résumé, sujets, série).
    public static func noticePage(key: String, id: Int) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "viewnotice", "clef", key, "id", String(id)])
    }

    /// Badge de disponibilité en temps réel (HTML).
    public static func availability(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["noticeajax", "availability", "id", String(recordID)])
    }

    /// Exemplaires en temps réel (HTML) : statut, cote, date de retour, réservations.
    public static func copies(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["noticeajax", "exemplaires", "id", String(recordID)])
    }

    /// Autocomplétion de la recherche.
    public static func suggest(_ prefix: String) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "suggestajax"], query: [FormField("startsWith", prefix)])
    }
}

// MARK: - Agenda et infos pratiques

extension Endpoint {
    /// Page Agenda (rendue côté serveur, contrairement à `/cms/calendar/...` qui se charge en AJAX).
    /// Les filtres sont les mêmes segments que sur le site.
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

// MARK: - Authentification

extension Endpoint {
    public static let loginPage = Endpoint(pathSegments: ["auth", "login"])

    public static func login(cardNumber: String, password: String, csrfToken: String) -> Endpoint {
        Endpoint(method: .post, pathSegments: ["auth", "login"], form: [
            FormField("username", cardNumber),
            FormField("password", password),
            FormField("login", "Se connecter"),
            FormField("csrftoken", csrfToken),
        ])
    }

    public static let lostPasswordPage = Endpoint(pathSegments: ["auth", "lostpass"])

    /// `website` est un champ piège anti-spam qui doit rester vide ; le formulaire
    /// doit être envoyé au moins `minimum_time` secondes après son affichage.
    public static func lostPassword(cardNumber: String, csrfToken: String) -> Endpoint {
        Endpoint(method: .post, pathSegments: ["auth", "lostpass"], form: [
            FormField("lost_username", cardNumber),
            FormField("website", ""),
            FormField("minimum_time", "2"),
            FormField("csrftoken", csrfToken),
        ])
    }

    public static let logout = Endpoint(pathSegments: ["auth", "logout"])
}

// MARK: - Compte abonné (JSON, avec le cookie de session)

extension Endpoint {
    public static let account = Endpoint(pathSegments: ["api", "user", "account"])
    public static let loans = Endpoint(pathSegments: ["api", "user", "loans"])
    public static let loansHistory = Endpoint(pathSegments: ["api", "user", "loans", "history"])
    public static let holds = Endpoint(pathSegments: ["api", "user", "holds"])

    /// Prolonge un ou plusieurs prêts (identifiants séparés par `;`).
    public static func renewLoans(patronID: String, loanIDs: [String]) -> Endpoint {
        Endpoint(pathSegments: [
            "abonne", "prolongerPret", "id_profil", "1", "id", patronID,
            "id_pret", loanIDs.joined(separator: ";"),
        ])
    }

    public static func cancelHold(holdID: String) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "reservations", "id_delete", holdID])
    }

    /// Page HTML des réservations : seule source du rang dans la file.
    public static func holdsPage(patronID: String) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "reservations", "id_profil", "1", "id", patronID])
    }

    public static func addToSelection(label: String, recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "ajouter-le-document-a-la-selection", "selection_label", label, "record_id", String(recordID)])
    }

    public static func bookmarkLibrary(libraryID: Int) -> Endpoint {
        Endpoint(pathSegments: ["abonne", "add-library-to-bookmarks", "library_id", String(libraryID)])
    }
}

// MARK: - Réservation (popups AJAX)

extension Endpoint {
    public static func holdOptions(recordID: Int) -> Endpoint {
        Endpoint(pathSegments: ["recherche", "reserver", "record_id", String(recordID), "render", "popup"], isAjax: true)
    }

    /// `path` est le lien `reservation-pickup-ajax/...` lu dans `holdOptions`.
    public static func pickupForm(path: String) -> Endpoint {
        Endpoint(pathSegments: path.split(separator: "/").map(String.init), isAjax: true)
    }

    public static func submitPickup(path: String, pickupLibraryCode: String) -> Endpoint {
        Endpoint(method: .post, pathSegments: path.split(separator: "/").map(String.init),
                 form: [FormField("code_annexe", pickupLibraryCode)], isAjax: true)
    }
}

// MARK: - Médiathèque numérique

extension Endpoint {
    /// Page minuscule `<script>document.location.href="…"</script>` qui porte l'URL SSO.
    public static func digitalModule(_ slug: String) -> Endpoint {
        Endpoint(pathSegments: ["modules", slug])
    }

    public static func digitalRecord(noticeID: Int) -> Endpoint {
        Endpoint(pathSegments: ["modules", "sso", "id", String(noticeID)])
    }
}
