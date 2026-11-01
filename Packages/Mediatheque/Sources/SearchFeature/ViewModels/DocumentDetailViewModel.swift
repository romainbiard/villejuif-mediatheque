// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import Foundation
import MediathequeCore
import Observation

@MainActor
@Observable
public final class DocumentDetailViewModel {
    public let document: Notice
    public private(set) var copies: LoadState<[LiveCopy]> = .idle

    @ObservationIgnored @Dependency(\.catalogClient) private var catalog

    public init(document: Notice) {
        self.document = document
    }

    public func load() async {
        guard !document.kind.isDigital else {
            copies = .loaded([])
            return
        }
        if copies.value == nil { copies = .loading }
        do {
            copies = .loaded(try await catalog.copies(document.id))
        } catch {
            copies = .failed(LoadError(error))
        }
    }

    /// Copies grouped by library, available ones first.
    public var copiesByLibrary: [(name: String, copies: [LiveCopy])] {
        let grouped = Dictionary(grouping: copies.value ?? [], by: \.libraryName)
        return grouped
            .map { (name: $0.key, copies: $0.value) }
            .sorted { lhs, rhs in
                let lhsAvailable = lhs.copies.contains { $0.status.isAvailable }
                let rhsAvailable = rhs.copies.contains { $0.status.isAvailable }
                return lhsAvailable != rhsAvailable ? lhsAvailable : lhs.name < rhs.name
            }
    }

    /// True if at least one copy can be placed on hold (pickup link present).
    public var isHoldable: Bool {
        copies.value?.contains { $0.pickupPath != nil } ?? false
    }
}
