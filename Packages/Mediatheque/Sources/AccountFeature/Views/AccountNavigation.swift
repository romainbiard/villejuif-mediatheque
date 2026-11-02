// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SearchFeature
import SwiftUI

enum AccountRoute: Hashable {
    case loans, holds
    case selections, selection(Selection), notice(Notice)
    case reviews, suggestions
    case information, settings
}

/// The 7 Mon compte sections, for the iPad sidebar.
public enum AccountSection: String, CaseIterable, Identifiable, Sendable {
    case loans, holds, selections, reviews, suggestions, information, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .loans: .local("Mes prêts")
        case .holds: .local("Mes réservations")
        case .selections: .local("Mes sélections")
        case .reviews: .local("Mes avis")
        case .suggestions: .local("Mes suggestions")
        case .information: .local("Mes informations")
        case .settings: .local("Mes configurations")
        }
    }

    public var systemImage: String {
        switch self {
        case .loans: "books.vertical"
        case .holds: "bookmark"
        case .selections: "heart"
        case .reviews: "star"
        case .suggestions: "lightbulb"
        case .information: "person.text.rectangle"
        case .settings: "gearshape"
        }
    }

    var route: AccountRoute {
        switch self {
        case .loans: .loans
        case .holds: .holds
        case .selections: .selections
        case .reviews: .reviews
        case .suggestions: .suggestions
        case .information: .information
        case .settings: .settings
        }
    }
}

extension EnvironmentValues {
    /// Set by the iPad sidebar, which already lists the Mon compte sections: the home doesn't repeat them.
    @Entry public var accountSectionsInSidebar = false
}

/// A Mon compte section opened on its own (sidebar tab on iPad).
/// Without a session, show the Account tab's sign-in.
public struct AccountSectionView: View {
    let section: AccountSection
    @Environment(SessionStore.self) private var session

    public init(_ section: AccountSection) {
        self.section = section
    }

    public var body: some View {
        if case let .loggedIn(patron) = session.state {
            NavigationStack {
                AccountDestination(route: section.route, patron: patron)
                    .navigationDestination(for: AccountRoute.self) { AccountDestination(route: $0, patron: patron) }
            }
        } else {
            AccountView()
        }
    }
}

struct AccountDestination: View {
    let route: AccountRoute
    let patron: Patron

    var body: some View {
        switch route {
        case .loans: LoansView()
        case .holds: HoldsView()
        case .selections: SelectionsView()
        case let .selection(selection): SelectionDetailView(selection: selection)
        case let .notice(notice): DocumentDetailView(document: notice)
        case .reviews: ReviewsView()
        case .suggestions: SuggestionsView()
        case .information: InformationView(patron: patron)
        case .settings: ProfileSettingsView(patron: patron)
        }
    }
}
