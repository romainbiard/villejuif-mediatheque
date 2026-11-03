// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

@MainActor
@Observable
final class DocumentDetailViewModel {
    let document: Notice
    private(set) var copies: LoadState<[LiveCopy]> = .idle
    /// Default selections holding the record; `nil` until read (signed out, or the page didn't load).
    private(set) var selections: Set<DefaultSelection>?
    private(set) var message: String?
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored @Dependency(\.catalogClient) private var catalog
    @ObservationIgnored @Dependency(\.profileClient) private var profile

    init(document: Notice) {
        self.document = document
    }

    func load() async {
        guard !document.kind.isDigital else {
            copies = .loaded([])
            return
        }
        if copies.value == nil { copies = .loading }
        do {
            copies = try await .loaded(catalog.copies(document.id))
        } catch {
            copies = .failed(LoadError(error))
        }
    }

    /// Reads which default selections hold the record. Only once signed in: the site answers for the patron.
    func loadSelections() async {
        selections = try? await profile.defaultSelections(document.id)
    }

    func isIn(_ selection: DefaultSelection) -> Bool {
        selections?.contains(selection) ?? false
    }

    /// Puts the record in the selection or takes it out. The heart changes at once,
    /// and comes back if the site refuses.
    func toggle(_ selection: DefaultSelection) async {
        guard let before = selections else { return }
        let isIn = !before.contains(selection)
        selections = isIn ? before.union([selection]) : before.subtracting([selection])
        feedback = .lightImpact
        do {
            try await profile.setInDefaultSelection(selection, document.id, isIn)
            message = isIn
                ? String.local("Ajouté à « \(selection.name) »", comment: "Toast; %@ is a selection name")
                : String.local("Retiré de « \(selection.name) »", comment: "Toast; %@ is a selection name")
        } catch {
            selections = before
            message = String.local("La sélection n'a pas pu être modifiée")
            feedback = .error
        }
    }

    func dismissMessage() {
        message = nil
    }

    /// Copies grouped by library, available ones first.
    var copiesByLibrary: [(name: String, copies: [LiveCopy])] {
        let grouped = Dictionary(grouping: copies.value ?? [], by: \.libraryName)
        return grouped
            .map { (name: $0.key, copies: $0.value) }
            .sorted { lhs, rhs in
                let lhsAvailable = lhs.copies.contains { $0.status.isAvailable }
                let rhsAvailable = rhs.copies.contains { $0.status.isAvailable }
                return lhsAvailable != rhsAvailable ? lhsAvailable : lhs.name < rhs.name
            }
    }
}
