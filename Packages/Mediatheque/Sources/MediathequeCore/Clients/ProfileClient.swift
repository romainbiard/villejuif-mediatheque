// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Dependencies
import DependenciesMacros
import Foundation

/// Patron space other than loans and holds: selections, reviews, suggestions, contact details, preferences.
/// These sections only exist as HTML (`/abonne/...`), read with the web session.
@DependencyClient
public struct ProfileClient: Sendable {
    public var selections: @Sendable () async throws -> [Selection]
    public var selectionNotices: @Sendable (_ selection: Selection, _ page: Int) async throws -> SearchPage
    public var createSelection: @Sendable (_ name: String) async throws -> Void
    public var removeFromSelection: @Sendable (_ selection: Selection, _ recordID: Int) async throws -> Void

    public var recordsToRate: @Sendable () async throws -> [RecordToRate]
    public var reviews: @Sendable () async throws -> [Review]
    public var submitReview: @Sendable (_ record: RecordToRate, _ rating: Int, _ title: String, _ text: String) async throws -> Void

    public var suggestions: @Sendable () async throws -> [Suggestion]
    public var sendSuggestion: @Sendable (_ draft: SuggestionDraft) async throws -> Void

    public var contactDetails: @Sendable () async throws -> ContactDetails
    public var updateContactDetails: @Sendable (_ details: ContactDetails) async throws -> Void
    public var changePassword: @Sendable (_ newPassword: String) async throws -> Void

    public var bookmarkedLibraries: @Sendable () async throws -> Set<Library>
    public var setLibraryBookmarked: @Sendable (_ library: Library, _ isBookmarked: Bool) async throws -> Void
    public var setNewsletterSubscribed: @Sendable (_ isSubscribed: Bool) async throws -> Void
}

extension ProfileClient: DependencyKey {
    /// The network's newsletter, the only one the site offers (checked on 31/10/2026).
    static let newsletterID = 3

    public static var liveValue: ProfileClient {
        @Dependency(\.httpClient) var http
        @Dependency(\.sessionManager) var session

        @Sendable func patronID() async throws -> String {
            let account = try await http.decode(AccountResponseDTO.self, from: .account).account
            guard let id = account.cards?.first?.id else { throw ProfileError.missingPatronID }
            return String(id)
        }

        @Sendable func page(_ name: String) async throws -> String {
            try await session.perform { try await http.string(for: .patronPage(name, patronID: try await patronID())) }
        }

        /// Submits a form and surfaces the first error message shown by the site.
        @Sendable func submit(_ name: String, _ fields: [Endpoint.FormField]) async throws {
            try await session.perform {
                let html = try await http.string(for: .patronForm(name, patronID: try await patronID(), fields: fields))
                if let error = try HTMLParsers.formErrors(in: html).first { throw ProfileError.rejected(error) }
            }
        }

        return ProfileClient(
            selections: {
                try HTMLParsers.selections(in: try await page("selections")).map(Selection.init(dto:))
            },
            selectionNotices: { selection, pageNumber in
                guard let basketID = selection.basketID else {
                    return SearchPage(total: 0, page: 1, pageSize: 10, documents: [])
                }
                return try await session.perform {
                    SearchPage(dto: try await http.decode(SearchResponseDTO.self, from: .selectionRecords(basketID: basketID, page: pageNumber)))
                }
            },
            createSelection: { name in
                try await submit("creer-selection", [.init("libelle", name)])
            },
            removeFromSelection: { selection, recordID in
                _ = try await session.perform {
                    try await http.data(for: .removeFromSelection(patronID: try await patronID(), selectionID: selection.id, recordID: recordID))
                }
            },
            recordsToRate: {
                try HTMLParsers.recordsToRate(in: try await page("donner-des-avis")).map(RecordToRate.init(dto:))
            },
            reviews: {
                try HTMLParsers.reviews(in: try await page("mes-avis")).enumerated().map { index, dto in
                    Review(id: "\(dto.recordID ?? 0)-\(index)", recordID: dto.recordID, title: dto.title, text: dto.text, rating: dto.rating)
                }
            },
            submitReview: { record, rating, title, text in
                _ = try await session.perform {
                    try await http.data(for: .submitReview(recordID: record.recordID, recordKey: record.recordKey, rating: rating, title: title, text: text))
                }
            },
            suggestions: {
                try HTMLParsers.suggestions(in: try await page("suggestions")).enumerated().map { index, dto in
                    Suggestion(id: "\(index)-\(dto.title)", title: dto.title, detail: dto.detail)
                }
            },
            sendSuggestion: { draft in
                // The "Site" field is prefilled with the patron's library: we send its value back.
                let library = try HTMLParsers.fieldValue("Library", in: try await page("suggestion-achat-add")) ?? ""
                let comment = draft.kind == .comic ? ["Bande dessinée", draft.comment].filter { !$0.isEmpty }.joined(separator: ". ") : draft.comment
                try await submit("suggestion-achat-add", [
                    .init("DocType", draft.kind.docTypeCode),
                    .init("Title", draft.title),
                    .init("Author", draft.author),
                    .init("Isbn", draft.isbn),
                    .init("Library", library),
                    .init("Url", ""),
                    .init("Comment", comment),
                    .init("submit", "Envoyer"),
                ])
            },
            contactDetails: {
                let html = try await page("modifier")
                return ContactDetails(
                    nickname: try HTMLParsers.fieldValue("pseudo", in: html) ?? "",
                    email: try HTMLParsers.fieldValue("mail", in: html) ?? "",
                    phone: try HTMLParsers.fieldValue("telephone", in: html) ?? "",
                    channel: SendingChannel(rawValue: try HTMLParsers.checkedValue("favoriteSendingChannel", in: html) ?? "") ?? .any
                )
            },
            updateContactDetails: { details in
                try await submit("modifier", [
                    .init("pseudo", details.nickname),
                    .init("mail", details.email),
                    .init("telephone", details.phone),
                    .init("favoriteSendingChannel", details.channel.rawValue),
                ])
            },
            changePassword: { newPassword in
                try await submit("changer-mon-mot-de-passe", [
                    .init("new_password", newPassword),
                    .init("confirm_new_password", newPassword),
                ])
            },
            bookmarkedLibraries: {
                let ids = try HTMLParsers.bookmarkedLibraryIDs(in: try await page("configurations"))
                return Set(ids.compactMap { Library(rawValue: String($0)) })
            },
            setLibraryBookmarked: { library, isBookmarked in
                guard let id = Int(library.rawValue) else { return }
                _ = try await session.perform {
                    try await http.data(for: isBookmarked ? .bookmarkLibrary(libraryID: id) : .removeLibraryBookmark(libraryID: id))
                }
            },
            setNewsletterSubscribed: { isSubscribed in
                _ = try await session.perform {
                    try await http.data(for: isSubscribed
                        ? .subscribeNewsletter(id: newsletterID)
                        : .patronPage("disable-newsletter", patronID: try await patronID()))
                }
            }
        )
    }

    public static let previewValue = ProfileClient(
        selections: { SampleData.selections },
        selectionNotices: { _, page in
            SearchPage(total: SampleData.documents.count, page: page, pageSize: 10, documents: SampleData.documents)
        },
        createSelection: { _ in },
        removeFromSelection: { _, _ in },
        recordsToRate: { SampleData.recordsToRate },
        reviews: { [] },
        submitReview: { _, _, _, _ in },
        suggestions: { [] },
        sendSuggestion: { _ in },
        contactDetails: {
            ContactDetails(nickname: "", email: "camille.martin@exemple.fr", phone: "06 00 00 00 00", channel: .email)
        },
        updateContactDetails: { _ in },
        changePassword: { _ in },
        bookmarkedLibraries: { [.pulpNord] },
        setLibraryBookmarked: { _, _ in },
        setNewsletterSubscribed: { _ in }
    )

    public static let testValue = ProfileClient()
}

extension DependencyValues {
    public var profileClient: ProfileClient {
        get { self[ProfileClient.self] }
        set { self[ProfileClient.self] = newValue }
    }
}

extension Selection {
    init(dto: SelectionDTO) {
        self.init(
            id: dto.id,
            basketID: dto.basketID,
            name: dto.title,
            count: dto.count,
            updatedAt: dto.updatedText.flatMap(BokehDates.firstDate),
            coverURLs: dto.coverURLs
        )
    }
}

extension RecordToRate {
    init(dto: RecordToRateDTO) {
        self.init(recordID: dto.recordID, recordKey: dto.recordKey, title: dto.title, author: dto.author, coverURL: dto.coverURL)
    }
}
