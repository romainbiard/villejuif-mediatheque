// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import SwiftSoup

// MARK: - DTOs extracted from the HTML

/// An event from `/cms/calendar/id_module/30` (an "Article" card).
public struct CalendarEventDTO: Sendable, Equatable {
    public let articleID: Int
    public let title: String
    public let imageURL: URL?
    public let location: String?
    /// Raw text of the "31/10/2026 à 10:30" or "26/09/2026" badges.
    public let startText: String?
    public let endText: String?
    public let eventType: String?
    public let audience: String?
    /// Full sentence shown by the site, e.g. "Samedi 31 octobre 2026 de 10:30 à 11:00".
    public let dateSentence: String?
}

/// A copy from `/noticeajax/exemplaires/id/{id}`.
public struct CopyDTO: Sendable, Equatable {
    public let libraryName: String
    public let availability: String
    public let section: String?
    public let location: String?
    public let shelfMark: String?
    /// "17/11/2026".
    public let dueDateText: String?
    /// "Déjà 2 réservations".
    public let holdsText: String?
    public let medium: String?
    /// `recherche/reservation-pickup-ajax/...` link (without a leading `/`), absent if it can't be placed on hold.
    public let pickupPath: String?
}

/// A library from the Infos pratiques page.
public struct LibraryDTO: Sendable, Equatable {
    public let slug: String
    public let name: String
    public let addressLines: [String]
    public let phone: String?
    public let contactURL: URL?
    /// "Mardi : 13h - 19h" lines.
    public let openingHours: [String]
    public let bookmarkLibraryID: Int?
}

/// A pickup location offered when placing a hold (`code_annexe`).
public struct PickupOptionDTO: Sendable, Equatable {
    public let code: String
    public let label: String
    public let isSelected: Bool
}

// MARK: - Parsers

public enum HTMLParsers {
    /// CSRF token of the forms (`auth/login`, `auth/lostpass`).
    public static func csrfToken(in html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        guard let token = try document.select("input[name=csrftoken]").first()?.attr("value"), !token.isEmpty else {
            throw BokehError.unexpectedFormat("csrftoken introuvable")
        }
        return token
    }

    /// True only when the page carries the portal's explicit refusal of the credentials, shown under
    /// the card number field after the sign-in form: "L'identifiant ou le mot de passe est invalide."
    /// Anything else (other page, other error) is not a refusal: the stored password must survive it.
    public static func loginRejected(in html: String) throws -> Bool {
        let document = try SwiftSoup.parse(html)
        return try document.select("li.element_error_message, ul.element_error_messages li").array().contains { item in
            let text = try item.text().lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            return text.contains("identifiant ou le mot de passe est invalide")
        }
    }

    /// True if the page shows a sign-in form in the main content (sign-in failed).
    public static func isLoggedIn(_ html: String) throws -> Bool {
        let document = try SwiftSoup.parse(html)
        return try !document.select("a[href*=/auth/logout], a[href*=logout]").isEmpty()
    }

    public static func calendarEvents(in html: String) throws -> [CalendarEventDTO] {
        let document = try SwiftSoup.parse(html, HTTPClient.villejuifBaseURL.absoluteString)
        var seen = Set<Int>()
        var events: [CalendarEventDTO] = []
        for card in try document.select("div.card_Intonation_Library_View_Wrapper_Article") {
            guard
                let link = try card.select(".card-title a[href*=articleview]").first(),
                let articleID = Int(try link.attr("href").split(separator: "/").last ?? ""),
                seen.insert(articleID).inserted
            else { continue }

            try link.select(".sr-only").remove()
            events.append(CalendarEventDTO(
                articleID: articleID,
                title: try link.text(),
                imageURL: URL(string: try card.select("img.card-img").first()?.attr("abs:src") ?? ""),
                location: try badgeText(card, ".badge_article_location"),
                startText: try badgeText(card, ".badge_event_start"),
                endText: try badgeText(card, ".badge_event_end"),
                eventType: try badgeText(card, ".custom_field_meta_2"),
                audience: try badgeText(card, ".custom_field_meta_3"),
                dateSentence: try card.select("span.calendar_event_date").first()?.text()
            ))
        }
        return events
    }

    public static func copies(in html: String) throws -> [CopyDTO] {
        let document = try SwiftSoup.parse(html)
        return try document.select("div.card_Intonation_Library_View_Wrapper_Item").map { card in
            CopyDTO(
                libraryName: try card.select(".card-title a").first()?.ownText().trimmingCharacters(in: .whitespaces) ?? "",
                availability: try card.select(".item_availability").first()?.text() ?? "",
                section: try badgeText(card, ".badge_section"),
                location: try badgeText(card, ".badge_emplacement"),
                shelfMark: try badgeText(card, ".badge_cote"),
                dueDateText: try badgeText(card, ".badge_retour"),
                holdsText: try badgeText(card, ".item_hold_rank"),
                medium: try badgeText(card, ".datas_items_995_r"),
                pickupPath: try card.select("a[href*=reservation-pickup-ajax]").first()
                    .map { String(try $0.attr("href").drop { $0 == "/" }) }
            )
        }
    }

    /// Badge from `/noticeajax/availability/id/{id}`: label and availability.
    public static func availability(in html: String) throws -> (label: String, isAvailable: Bool) {
        let document = try SwiftSoup.parse(html)
        guard let badge = try document.select(".badge_record_availability").first() else {
            throw BokehError.unexpectedFormat("badge de disponibilité introuvable")
        }
        return (try badge.text(), !badge.hasClass("record_not_available"))
    }

    public static func libraries(in html: String) throws -> [LibraryDTO] {
        let document = try SwiftSoup.parse(html, HTTPClient.villejuifBaseURL.absoluteString)
        var seen = Set<String>()
        var libraries: [LibraryDTO] = []
        for card in try document.select("div.card_Intonation_Library_View_Wrapper_Library") {
            guard let link = try card.select(".card-title a").first() else { continue }
            let slug = String(try link.attr("href").drop { $0 == "/" })
            guard seen.insert(slug).inserted else { continue }

            // The site separates lines with an invalid `</br>`: we read the text nodes one by one.
            let addressLines = (try card.select(".badge_address .badge_text").first()?.textNodes() ?? [])
                .map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            libraries.append(LibraryDTO(
                slug: slug,
                name: link.ownText(),
                addressLines: addressLines,
                phone: try badgeText(card, ".badge_phone"),
                contactURL: try contactURL(in: card),
                openingHours: try card.select(".default_opening_hours ul li").map { try $0.text() },
                bookmarkLibraryID: try card.select("a[href*=add-library-to-bookmarks]").first()
                    .flatMap { Int(try $0.attr("href").split(separator: "/").last ?? "") }
            ))
        }
        return libraries
    }

    /// Pickup locations from the `reservation-pickup-ajax` form (contents of a `PopupDTO`).
    public static func pickupOptions(in html: String) throws -> [PickupOptionDTO] {
        let document = try SwiftSoup.parse(html)
        return try document.select("input[name=code_annexe]").map { input in
            let id = try input.attr("id")
            let label = try (id.isEmpty ? nil : document.select("label[for=\(id)]").first())
                ?? input.parent()
            return PickupOptionDTO(
                code: try input.attr("value"),
                label: try label?.text() ?? "",
                isSelected: input.hasAttr("checked")
            )
        }
    }

    /// Per-copy hold links in `recherche/reserver/.../render/popup`.
    public static func holdPickupPaths(in html: String) throws -> [String] {
        let document = try SwiftSoup.parse(html)
        let paths = try document.select("a[href*=reservation-pickup-ajax]").map {
            String(try $0.attr("href").drop { $0 == "/" })
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// "Rang N" positions shown on the "Mes réservations" page, in hold order.
    /// The page has only been seen with a single hold: the rank ↔ hold mapping
    /// is done by order of appearance.
    public static func holdRanks(in html: String) throws -> [Int] {
        let text = try SwiftSoup.parse(html).text()
        return text.matches(of: /Rang\s+(\d+)/).compactMap { Int($0.1) }
    }

    /// Provider URL carried by a `/modules/{service}` page.
    public static func ssoTarget(in html: String) -> URL? {
        let pattern = /location\.href\s*=\s*"([^"]+)"/
        guard let match = html.firstMatch(of: pattern) else { return nil }
        return URL(string: String(match.1))
    }

    // MARK: Utilities

    /// The site nests a link inside the badge's `mailto:` (`mailto:<a href="https://…">`):
    /// we extract the contact form URL straight from the attribute.
    private static func contactURL(in card: Element) throws -> URL? {
        guard let href = try card.select("a.badge_mail").first()?.attr("href"),
              let match = href.firstMatch(of: /https?:\/\/[^"'<>\s]+/)
        else { return nil }
        return URL(string: String(match.0))
    }

    private static func badgeText(_ element: Element, _ selector: String) throws -> String? {
        guard let badge = try element.select("\(selector) .badge_text").first() else { return nil }
        try badge.select(".sr-only").remove()
        let text = try badge.text().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
