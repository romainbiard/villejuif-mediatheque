// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import CoreUI
import DesignSystem
import MediathequeCore
import SwiftUI

/// Account tab: sign-in, or the account home once the session is open.
public struct AccountView: View {
    @Environment(SessionStore.self) private var session
    /// Set to `true` ("Montrer ma carte" shortcut): shows the card full screen, then resets to `false`.
    @Binding private var cardRequest: Bool

    public init(cardRequest: Binding<Bool> = .constant(false)) {
        _cardRequest = cardRequest
    }

    public var body: some View {
        switch session.state {
        case .restoring:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.surfaceGrouped)
        case .locked:
            LockedView()
        case .loggedOut:
            LoginView()
        case let .loggedIn(patron):
            AccountHomeView(patron: patron, cardRequest: $cardRequest)
        }
    }
}

struct AccountHomeView: View {
    let patron: Patron
    @Binding var cardRequest: Bool
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AccountHomeViewModel()
    @State private var showsCard = false
    @State private var showsNotifications = false
    @State private var path = NavigationPath()
    @State private var confirmsLogout = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accountSectionsInSidebar) private var sectionsInSidebar
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var contentWidth: CGFloat = .infinity
    /// iPad only: loans due and the hold ready for pickup, shown on the home itself.
    @State private var loans = LoansViewModel()
    @State private var holds = HoldsViewModel()
    @AppStorage(ReminderSettings.Key.onboardingDone, store: .shared) private var onboardingDone = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if sizeClass == .regular {
                    dashboard
                        .frame(maxWidth: Self.dashboardMaxWidth)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        staleBanner
                        expiryBanner
                        card
                        counters
                        menu
                        logoutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(Text(.local("Mon compte")))
            .navigationDestination(for: AccountRoute.self) { AccountDestination(route: $0, patron: patron) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsNotifications = true } label: {
                        if viewModel.unreadNotifications > 0 {
                            Image(systemName: "bell.badge")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.brandMagenta, Color.ink)
                        } else {
                            Image(systemName: "bell")
                        }
                    }
                    .accessibilityLabel(viewModel.unreadNotifications > 0
                        ? Text(.local("Notifications, \(viewModel.unreadNotifications) non lues"))
                        : Text(.local("Notifications")))
                }
            }
            .sheet(isPresented: $showsNotifications, onDismiss: viewModel.refreshUnreadCount) {
                NotificationsView {
                    showsNotifications = false
                    path.append(AccountRoute.settings)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .overlay(alignment: .bottom) { MessageToast(message: loans.message) { loans.dismissMessage() } }
            .fullScreenCover(isPresented: $showsCard) { FullScreenCardView(patron: patron) }
            .onChange(of: cardRequest, initial: true) {
                guard cardRequest else { return }
                showsCard = true
                cardRequest = false
            }
            // Full screen: the notifications explanation reuses the sign-in layout.
            .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
                WelcomeSetupView { onboardingDone = true }
            }
        }
        .measuringWidth($contentWidth)
        .sensoryFeedback(.impact(weight: .medium), trigger: session.state == .loggedOut)
        .sensoryFeedback(trigger: loans.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    /// Content of the iPad home, centered: nothing stretches on a 13-inch iPad or a full-screen window.
    static let dashboardMaxWidth: CGFloat = 900
    /// The card keeps the size of a real card instead of filling the column.
    static let cardWidth: CGFloat = 340
    /// Card next to the counters and loans in two columns from this width (the detail column
    /// of an 11-inch iPad in landscape, next to the sidebar, is about 830 pt).
    static let wideMinWidth: CGFloat = 700

    private var isWide: Bool { contentWidth >= Self.wideMinWidth }

    private func refresh() async {
        await viewModel.refresh(session)
        guard sizeClass == .regular else { return }
        async let loansLoad: Void = loans.load()
        async let holdsLoad: Void = holds.load()
        _ = await (loansLoad, holdsLoad)
    }

    // MARK: iPad

    /// iPad home: the card at its real size with the counters and the hold to pick up next to it,
    /// then the loans due and the library's message. The sections are already in the sidebar,
    /// so the menu only appears when there is no sidebar (narrow window).
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            staleBanner
            expiryBanner
            if isWide {
                HStack(alignment: .top, spacing: 18) {
                    card.frame(width: Self.cardWidth)
                    VStack(spacing: 12) {
                        counters
                        readyHold
                    }
                }
            } else {
                card
                counters
                readyHold
            }
            dueLoans
            libraryMessage
            if !sectionsInSidebar { menu }
            sessionCard
        }
    }

    /// Who is signed in, with a real Sign out button: on iPad, a lone red link floated mid-screen.
    private var sessionCard: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.brandViolet, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(.local("Connecté en tant que")).font(.footnote).foregroundStyle(Color.inkSecondary)
                Text(patron.displayName).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button(.local("Se déconnecter"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirmsLogout = true
            }
            .buttonStyle(.bordered)
            .tint(.statusDanger)
            .fixedSize()
            // Attached to the button: on iOS 26 the confirmation is a popover pointing at its view.
            .confirmationDialog(Text(.local("Se déconnecter de votre compte ?")), isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button(.local("Se déconnecter"), role: .destructive) { Task { await session.logout() } }
            }
        }
        .cardStyle()
        .padding(.top, 6)
    }

    private var initials: String {
        [patron.firstName, patron.lastName].compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    @ViewBuilder
    private var readyHold: some View {
        if holds.state.value == nil, !holds.state.isFailed {
            // Same footprint as the card below, so nothing jumps when holds arrive.
            SkeletonRow()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if let hold = holds.state.value?.first(where: \.isReadyForPickup) {
            NavigationLink(value: AccountRoute.holds) {
                HStack(spacing: 14) {
                    CoverImage(url: hold.coverURL, title: hold.title, seed: hold.recordID ?? 0)
                        .frame(width: 46, height: 66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.local("Prête à retirer"))
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.statusSuccess)
                        Text(hold.title).font(.headline).foregroundStyle(Color.ink).lineLimit(2)
                        Text(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.inkSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.statusSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// The next loans due, with Renew: what you come to the Account tab for.
    private var dueLoans: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(.local("À rendre")) {
                if let all = loans.state.value, all.count > 1 {
                    Button(.local("Tout prolonger")) { Task { await loans.renewAll() } }
                        .font(.subheadline.weight(.semibold))
                        .disabled(!loans.renewing.isEmpty)
                }
            }
            switch loans.state {
            case .idle, .loading:
                loanGrid {
                    // Placeholders shaped like loan cards while the loans load, as many as the
                    // account counter announces: the grid keeps its height when they arrive.
                    ForEach(0..<min(max(patron.counters.loans, 1), Self.dueLoansShown), id: \.self) { _ in
                        SkeletonRow().padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(padding: 0)
                    }
                }
            case let .failed(error):
                HStack(spacing: 12) {
                    Image(systemName: error.systemImage)
                        .foregroundStyle(Color.statusWarning)
                    Text(error.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 8)
                    Button(.local("Réessayer")) { Task { await loans.load() } }
                        .font(.subheadline.weight(.semibold))
                }
                .cardStyle()
            case let .loaded(all) where all.isEmpty:
                Label(.local("Rien à rendre pour l'instant"), systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            case let .loaded(all):
                loanGrid {
                    ForEach(all.prefix(Self.dueLoansShown)) { loan in
                        LoanRow(loan: loan, viewModel: loans).cardStyle(padding: 0)
                    }
                }
                if all.count > Self.dueLoansShown {
                    NavigationLink(value: AccountRoute.loans) {
                        Text(.local("Voir les \(all.count) prêts")).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func loanGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: isWide ? 2 : 1),
            spacing: 12,
            content: content
        )
    }

    static let dueLoansShown = 4

    @ViewBuilder
    private var libraryMessage: some View {
        if let message = patron.message, !message.isEmpty {
            Button { showsNotifications = true } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(Color.brandVioletDeep)
                        .frame(width: 36, height: 36)
                        .background(Color.brandViolet.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.local("Message de la médiathèque")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                        Text(message).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Shared

    /// The account couldn't be refreshed: what is on screen is the last one read.
    @ViewBuilder
    private var staleBanner: some View {
        if let error = viewModel.error, error != .notLoggedIn {
            StaleBanner(error: error)
        }
    }

    @ViewBuilder
    private var expiryBanner: some View {
        if patron.cardExpired || patron.cardAboutToExpire {
            CardExpiryBanner(patron: patron)
        }
    }

    private var card: some View {
        Button { showsCard = true } label: { LibraryCardView(patron: patron) }
            .buttonStyle(.plain)
            .accessibilityHint(Text(.local("Affiche la carte en grand pour le comptoir")))
    }

    private var logoutButton: some View {
        Button(.local("Se déconnecter"), role: .destructive) { confirmsLogout = true }
            // Attached to the button: on iOS 26 the confirmation is a popover pointing at its view.
            .confirmationDialog(Text(.local("Se déconnecter de votre compte ?")), isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button(.local("Se déconnecter"), role: .destructive) { Task { await session.logout() } }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private var counters: some View {
        // Side by side, stacked at accessibility text sizes (labels would be cut off).
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            NavigationLink(value: AccountRoute.loans) {
                CounterTile(value: patron.counters.loans, label: .local("Prêts"), color: .ink)
            }
            NavigationLink(value: AccountRoute.loans) {
                CounterTile(value: patron.counters.lateLoans, label: .local("En retard"), color: .statusDanger)
            }
            NavigationLink(value: AccountRoute.holds) {
                CounterTile(value: patron.counters.waitingToBePulled, label: .local("À retirer"), color: .statusSuccess)
            }
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(.local("Mes emprunts"))
            VStack(spacing: 0) {
                NavigationLink(value: AccountRoute.loans) {
                    MenuRow(title: .local("Mes prêts"), systemImage: "books.vertical.fill", tint: .brandViolet) {
                        if patron.counters.lateLoans > 0 {
                            StatusPill(.local("\(patron.counters.lateLoans) en retard"), style: .danger)
                        }
                    }
                }
                Divider().padding(.leading, 58)
                NavigationLink(value: AccountRoute.holds) {
                    MenuRow(title: .local("Mes réservations"), systemImage: "bookmark.fill", tint: .statusSuccess) {
                        if patron.counters.waitingToBePulled > 0 {
                            StatusPill(.local("\(patron.counters.waitingToBePulled) à retirer"), style: .success)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 0)

            SectionHeader(.local("Mes listes")).padding(.top, 10)
            VStack(spacing: 0) {
                menuLink(.selections, .local("Mes sélections"), "heart.fill", .brandMagenta)
                Divider().padding(.leading, 58)
                menuLink(.reviews, .local("Mes avis"), "star.fill", .statusWarning)
                Divider().padding(.leading, 58)
                menuLink(.suggestions, .local("Mes suggestions d'achat"), "lightbulb.fill", .brandVioletDeep)
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 0)

            SectionHeader(.local("Mon profil")).padding(.top, 10)
            VStack(spacing: 0) {
                menuLink(.information, .local("Mes informations"), "person.text.rectangle.fill", .ink)
                Divider().padding(.leading, 58)
                menuLink(.settings, .local("Mes configurations"), "gearshape.fill", .inkSecondary)
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 0)
        }
    }

    private func menuLink(_ route: AccountRoute, _ title: String, _ systemImage: String, _ tint: Color) -> some View {
        NavigationLink(value: route) {
            MenuRow(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
        }
    }
}
