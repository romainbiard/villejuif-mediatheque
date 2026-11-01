// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import SwiftSoup

// `/abonne/*` pages of the patron space, checked on 31/10/2026.

/// A card from `/abonne/selections`.
public struct SelectionDTO: Sendable, Equatable {
    public let id: Int
    /// Search basket, present as soon as the selection contains a document.
    public let basketID: Int?
    public let title: String
    public let count: Int
    /// "30/10/2026".
    public let updatedText: String?
    public let coverURLs: [URL]
    public let previewTitles: [String]
}

/// A borrowed document to rate (`/abonne/donner-des-avis`).
public struct RecordToRateDTO: Sendable, Equatable {
    public let recordID: Int
    public let recordKey: String
    public let title: String
    public let author: String?
    public let coverURL: URL?
}

/// A published review (`/abonne/mes-avis`).
/// ⚠️ Read from an account with no reviews: a card's structure is assumed to be identical
/// to the other Intonation lists (title linked to the record, text, stars).
public struct ReviewDTO: Sendable, Equatable {
    public let recordID: Int?
    public let title: String
    public let text: String
    public let rating: Int?
}

/// A sent purchase suggestion (`/abonne/suggestions`).
/// ⚠️ Read from an account with no suggestions: the structure is assumed.
public struct SuggestionDTO: Sendable, Equatable {
    public let title: String
    public let detail: String?
}

extension HTMLParsers {
    public static func selections(in html: String) throws -> [SelectionDTO] {
        let document = try SwiftSoup.parse(html, HTTPClient.villejuifBaseURL.absoluteString)
        return try document.select("div.card_title_Intonation_Library_View_Wrapper_Selection").compactMap { title in
            guard let card = title.parents().first(where: { $0.hasClass("card") }) else { return nil }
            let hrefs = try card.select("a[href]").map { try $0.attr("href") }
            guard let id = hrefs.lazy.compactMap({ firstInt(after: "selection_id/", in: $0) }).first else { return nil }

            let link = try title.select("a").first()
            try link?.select(".sr-only").remove()
            return SelectionDTO(
                id: id,
                basketID: hrefs.lazy.compactMap { firstInt(after: "id_panier/", in: $0) }.first,
                title: try link?.text() ?? "",
                count: Int(try card.select(".selection_count_records .badge").first()?.text() ?? "") ?? 0,
                updatedText: try card.select(".selection_date_maj .badge").first()?.text(),
                coverURLs: try card.select(".cardify_horizontal_img img").compactMap { URL(string: try $0.attr("abs:src")) },
                previewTitles: try card.select("p.model_description_Class_PanierNotice").map { try $0.text() }
            )
        }
    }

    /// Borrowed documents offered for rating, with their `ajax-review` form.
    public static func recordsToRate(in html: String) throws -> [RecordToRateDTO] {
        let document = try SwiftSoup.parse(html, HTTPClient.villejuifBaseURL.absoluteString)
        return try document.select("form[action*=ajax-review]").compactMap { form in
            let action = try form.attr("action")
            guard
                let recordID = firstInt(after: "record_id/", in: action),
                let key = segment(after: "record_key", in: action),
                let card = form.parents().first(where: { (try? $0.select(".cardify_horizontal_img").isEmpty()) == false })
            else { return nil }

            let title = try card.select(".card-title a").first()
            try title?.select(".sr-only").remove()
            let author = try card.select(".card-subtitle .d-inline").first()
            try author?.select(".sr-only").remove()
            return RecordToRateDTO(
                recordID: recordID,
                recordKey: key.removingPercentEncoding ?? key,
                title: try title?.text() ?? "",
                author: try author?.text().nilIfBlank,
                coverURL: URL(string: try card.select(".cardify_horizontal_img img").first()?.attr("abs:src") ?? "")
            )
        }
    }

    public static func reviews(in html: String) throws -> [ReviewDTO] {
        let document = try SwiftSoup.parse(html)
        guard let content = try document.select(".jumbotron_rich_content").first() else { return [] }
        return try content.select(".card").compactMap { card in
            guard let link = try card.select(".card-title a, a[href*=viewnotice]").first() else { return nil }
            try link.select(".sr-only").remove()
            let filledStars = try card.select(".fa-star.fas, .fas.fa-star, .star_on").size()
            return ReviewDTO(
                recordID: firstInt(after: "/id/", in: try link.attr("href")),
                title: try link.text(),
                text: try card.select(".card-text").first()?.text() ?? "",
                rating: filledStars > 0 ? filledStars : nil
            )
        }
    }

    public static func suggestions(in html: String) throws -> [SuggestionDTO] {
        let document = try SwiftSoup.parse(html)
        guard let content = try document.select(".jumbotron_rich_content").first() else { return [] }
        let rows = try content.select("table tbody tr")
        if !rows.isEmpty() {
            return try rows.map { row in
                let cells = try row.select("td").map { try $0.text() }.filter { !$0.isEmpty }
                return SuggestionDTO(title: cells.first ?? "", detail: cells.dropFirst().joined(separator: " · ").nilIfBlank)
            }
        }
        return try content.select(".card").compactMap { card in
            guard let title = try card.select(".card-title").first()?.text().nilIfBlank else { return nil }
            return SuggestionDTO(title: title, detail: try card.select(".card-text").first()?.text().nilIfBlank)
        }
    }

    /// Favorite libraries: those that offer the "retirer des favoris" link.
    public static func bookmarkedLibraryIDs(in html: String) throws -> Set<Int> {
        let document = try SwiftSoup.parse(html)
        return Set(try document.select("a[href*=remove-library-from-bookmarks]").compactMap {
            firstInt(after: "library_id/", in: try $0.attr("href"))
        })
    }

    /// Prefilled value of a form field (e.g. `Library` in the purchase suggestion).
    public static func fieldValue(_ name: String, in html: String) throws -> String? {
        try SwiftSoup.parse(html).select("[name=\(name)]").first()?.attr("value").nilIfBlank
    }

    /// Value of the checked radio button (e.g. `favoriteSendingChannel`).
    public static func checkedValue(_ name: String, in html: String) throws -> String? {
        try SwiftSoup.parse(html).select("input[name=\(name)][checked]").first()?.attr("value")
    }

    /// Error messages of a form returned by the site (invalid fields, password rejected…).
    public static func formErrors(in html: String) throws -> [String] {
        let document = try SwiftSoup.parse(html)
        return try document.select(".jumbotron_rich_content ul.errors li, .jumbotron_rich_content .alert-danger, .jumbotron_rich_content .error")
            .map { try $0.text() }
            .filter { !$0.isEmpty }
    }

    /// Segment following `name` in a Bokeh `/cle/valeur` path.
    private static func segment(after name: String, in path: String) -> String? {
        let segments = path.split(separator: "/")
        guard let index = segments.firstIndex(of: Substring(name)), segments.indices.contains(index + 1) else { return nil }
        return String(segments[index + 1])
    }

    private static func firstInt(after marker: String, in text: String) -> Int? {
        guard let range = text.range(of: marker) else { return nil }
        return Int(text[range.upperBound...].prefix { $0.isNumber })
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
