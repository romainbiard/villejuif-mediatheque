// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Foundation

// The only place that knows Bokeh's quirks: "Nom|Prénom" authors,
// "0000-00-00" dates, empty covers, free-text statuses.

extension Notice {
    init?(dto: RecordDTO) {
        guard let id = dto.noticeID else { return nil }
        self.init(
            id: id,
            title: dto.titles.last ?? dto.titles.first ?? "",
            authors: dto.creators.map(Notice.displayName(fromCreator:)),
            year: dto.date.isEmpty ? nil : dto.date,
            publisher: dto.publishers.first { !$0.isEmpty }.map(Notice.stripPlace),
            kind: DocumentKind(code: dto.type.code, label: dto.type.label),
            coverURL: dto.thumbnail.flatMap(nonEmptyURL),
            series: dto.serial,
            volume: dto.volume,
            permalink: URL(string: dto.permalink),
            harvestedCopies: dto.items.map {
                HarvestedCopy(library: $0.subfield("a").flatMap(Library.init(label:)) ?? $0.annex.flatMap(Library.init(rawValue:)))
            }
        )
    }

    /// "Rowling|Joanne Kathleen" → "Joanne Kathleen Rowling"; "Froment  jean" is left as is.
    static func displayName(fromCreator creator: String) -> String {
        let parts = creator.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return creator.trimmingCharacters(in: .whitespaces) }
        return "\(parts[1]) \(parts[0])"
    }

    /// "Gallimard jeunesse (Paris)" → "Gallimard jeunesse".
    static func stripPlace(_ publisher: String) -> String {
        publisher.replacing(/\s*\([^)]*\)\s*$/, with: "")
    }
}

extension SearchPage {
    init(dto: SearchResponseDTO) {
        self.init(total: dto.total, documents: dto.records.compactMap(Notice.init(dto:)))
    }
}

extension LiveCopy {
    init(dto: CopyDTO) {
        let label = dto.availability
        let normalized = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let status: CopyStatus = if normalized.contains("bientot") {
            // "Bientôt disponible": returned but not yet back on the shelf.
            .other(label)
        } else if normalized.contains("pret") {
            .onLoan(dueDate: dto.dueDateText.flatMap(BokehDates.firstDate))
        } else if normalized.contains("disponible") || normalized.contains("en rayon") {
            .available
        } else if normalized.contains("reserve") || normalized.contains("demander") {
            .onRequest
        } else {
            .other(label)
        }
        self.init(
            library: Library(label: dto.libraryName),
            libraryName: dto.libraryName,
            status: status,
            statusLabel: label,
            section: dto.section,
            shelfMark: dto.shelfMark,
            holdCount: LiveCopy.holdCount(from: dto.holdsText)
        )
    }

    /// "Déjà 2 réservations" → 2, "Déjà une réservation" → 1.
    static func holdCount(from text: String?) -> Int {
        guard let text else { return 0 }
        if let match = text.firstMatch(of: /(\d+)/) { return Int(match.1) ?? 0 }
        return text.localizedCaseInsensitiveContains("une réservation") ? 1 : 0
    }
}

extension Patron {
    init(dto: AccountDTO) {
        self.init(
            cardNumber: dto.login,
            firstName: dto.identity.firstName,
            lastName: dto.identity.lastName,
            email: dto.contact.email.nilIfEmpty,
            phone: dto.contact.mobile.nilIfEmpty ?? dto.contact.phone.nilIfEmpty,
            homeLibrary: Library(rawValue: String(dto.libraryDetails.id)) ?? Library(label: dto.libraryDetails.label),
            cardExpiry: BokehDates.isoDay(dto.card.expireAt),
            cardExpired: dto.card.expired,
            cardAboutToExpire: dto.card.aboutToExpire,
            cardExpiresInDays: dto.card.expiresIn,
            permissions: Permissions(
                holdForbidden: dto.permissions.holdForbidden,
                digitalResourcesForbidden: dto.permissions.digitalResourcesForbidden
            ),
            counters: Counters(
                loans: dto.counters.loans,
                lateLoans: dto.counters.lateLoans,
                waitingToBePulled: dto.counters.waitingToBePulled
            ),
            message: dto.message.content.nilIfEmpty,
            hasUnreadMessage: dto.message.unread,
            nickname: dto.identity.nickname?.nilIfEmpty,
            postalAddress: [dto.contact.address, "\(dto.contact.zipCode) \(dto.contact.city.capitalized)"]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
                .nilIfEmpty,
            newsletterSubscribed: !(dto.preferences?.newsletters.isEmpty ?? true)
        )
    }
}

extension Loan {
    init?(dto: LoanDTO) {
        guard let due = BokehDates.isoDay(dto.dateDue) else { return nil }
        self.init(
            id: dto.id,
            title: dto.title,
            author: dto.author,
            dueDate: due,
            library: Library(label: dto.library),
            libraryName: dto.library,
            recordID: dto.record?.id,
            coverURL: dto.record?.thumbnail.flatMap(nonEmptyURL)
        )
    }
}

extension Hold {
    init(dto: HoldDTO, rank: Int? = nil) {
        self.init(
            id: dto.id,
            title: Hold.cleanTitle(dto.title),
            statusText: dto.status ?? "",
            pickupLibrary: Library(label: dto.library),
            pickupLibraryName: dto.library,
            recordID: dto.record?.id,
            coverURL: dto.record?.thumbnail.flatMap(nonEmptyURL),
            rank: rank
        )
    }

    /// Bokeh glues the series and the title together ("Astérix n° 39Astérix et le griffon").
    static func cleanTitle(_ title: String) -> String {
        title.replacing(/^(.+? n° \d+)(?=\p{Lu})/) { "\($0.1) · " }
    }
}

extension Event {
    init(dto: CalendarEventDTO) {
        let start = dto.startText.flatMap(BokehDates.frenchDate)
        let end = dto.endText.flatMap(BokehDates.frenchDate)
        self.init(
            id: dto.articleID,
            title: dto.title,
            imageURL: dto.imageURL,
            place: dto.location,
            library: dto.location.flatMap(Library.init(label:)),
            start: start?.date,
            end: end?.date,
            isAllDay: start.map { !$0.hasTime } ?? true,
            type: dto.eventType,
            audience: dto.audience,
            dateDescription: dto.dateSentence
        )
    }
}

extension LibraryInfo {
    init(dto: LibraryDTO) {
        self.init(
            library: Library(slug: dto.slug),
            slug: dto.slug,
            name: dto.name,
            addressLines: dto.addressLines,
            phone: dto.phone,
            contactURL: dto.contactURL,
            hours: OpeningHours(lines: dto.openingHours),
            hourLines: dto.openingHours
        )
    }
}

private func nonEmptyURL(_ string: String) -> URL? {
    string.isEmpty ? nil : URL(string: string)
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
