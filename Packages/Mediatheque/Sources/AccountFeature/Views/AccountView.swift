// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SearchFeature
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
                WelcomeSetupView(patron: patron) { onboardingDone = true }
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
                    Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                        .foregroundStyle(Color.statusWarning)
                    Text(error == .offline ? String.local("Pas de connexion") : String.local("Impossible de charger vos prêts."))
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
        HStack(spacing: 10) {
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

// MARK: - Library card

struct LibraryCardView: View {
    let patron: Patron

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    VillejuifLogo.white.resizable().scaledToFit().frame(height: 26).accessibilityLabel(Text(.local("Ville de Villejuif")))
                    Text(patron.displayName).font(.title2.weight(.bold))
                    if let expiry = patron.cardExpiry {
                        Text(.local("Carte valable jusqu'au \(expiry.formatted(.dateTime.day().month(.wide).year()))"))
                            .font(.footnote)
                            .opacity(0.85)
                    }
                }
                Spacer()
                Text(.local("Gratuit"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 6) {
                BarcodeView(value: patron.cardNumber).frame(height: 44)
                HStack {
                    Text(patron.cardNumber).font(.footnote.weight(.semibold)).monospacedDigit().tracking(2)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text(.local("Toucher pour agrandir")).font(.footnote).foregroundStyle(Color(hex: 0x5E5B66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(Color(hex: 0x1C1B22))
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            ZStack {
                Color.brandViolet
                Circle().fill(Color.brandMagenta.opacity(0.55)).frame(width: 220).offset(x: 140, y: -110)
                Circle().fill(Color.brandVioletDeep.opacity(0.7)).frame(width: 120).offset(x: 170, y: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.local("Carte d'abonné de \(patron.displayName), numéro \(patron.cardNumber)")))
    }
}

/// Full-screen card for the front desk, brightness at maximum while it is displayed.
///
/// The barcode is vertical, against the right edge and the same size as the one on the plastic card:
/// any larger and it overflows the handheld scanner's window; at the edge, the phone can get close to the reader.
struct FullScreenCardView: View {
    let patron: Patron
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat?
    /// Barcode orientation chosen by the patron (depending on the reader), remembered between displays.
    @AppStorage("card.barcodeFlipped") private var isFlipped = true

    /// About 43 × 11 mm on iPhone, like the barcode printed on the card.
    static let barcodeLength: CGFloat = 260
    static let barcodeThickness: CGFloat = 64
    static let edgeInset: CGFloat = 14

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            HStack(spacing: 0) {
                identity
                Spacer(minLength: 16)
                barcode
            }
            .padding(.leading, 24)
            .padding(.trailing, Self.edgeInset)
        }
        .overlay(alignment: .trailing) {
            // Marker for the edge to present to the reader.
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2)
                .fill(Color.brandViolet.opacity(0.35))
                .frame(width: 4, height: Self.barcodeLength)
                .ignoresSafeArea(edges: .trailing)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            Button(.local("Fermer"), systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button(.local("Pivoter le code-barres"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                withAnimation(.smooth(duration: 0.35)) { isFlipped.toggle() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(.trailing, 20)
            .padding(.top, 8)
            .sensoryFeedback(.selection, trigger: isFlipped)
        }
        .overlay(alignment: .bottom) { hint }
        .foregroundStyle(Color(hex: 0x1C1B22))
        .onAppear(perform: brighten)
        .onDisappear(perform: restore)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.local("Carte d'abonné"))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.brandViolet)
            Text(patron.displayName).font(.title.weight(.heavy))
            Text(.local("Médiathèques de Villejuif")).font(.subheadline).foregroundStyle(Color(hex: 0x5E5B66))
            Text(.local("N° de carte"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: 0x5E5B66))
                .padding(.top, 18)
            Text(patron.cardNumber)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let expiry = patron.cardExpiry {
                Text(.local("Valable jusqu'au \(expiry.formatted(.dateTime.day().month(.wide).year()))"))
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x5E5B66))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var barcode: some View {
        HStack(spacing: 8) {
            // Human-readable number along the barcode, read bottom to top as on the card.
            Text(verbatim: "*\(patron.cardNumber)*")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .tracking(4)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.barcodeLength)
                .rotationEffect(.degrees(-90))
                .frame(width: 16, height: Self.barcodeLength)
                .accessibilityHidden(true)
            BarcodeView(value: patron.cardNumber, axis: .vertical)
                .frame(width: Self.barcodeThickness, height: Self.barcodeLength)
        }
        // Rotated a half turn by default: the number moves to the edge side and reads top to bottom.
        .rotationEffect(.degrees(isFlipped ? 180 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.local("Code-barres de la carte, numéro \(patron.cardNumber)")))
    }

    private var hint: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.brandViolet, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(.local("Approchez ce bord du lecteur")).font(.subheadline.weight(.semibold))
                Text(.local("Luminosité au maximum pendant l'affichage"))
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0x5E5B66))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: 0xF4F3F8), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func brighten() {
        #if canImport(UIKit)
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
        #endif
    }

    private func restore() {
        #if canImport(UIKit)
        guard let previousBrightness,
              let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first
        else { return }
        screen.brightness = previousBrightness
        #endif
    }
}

/// Barcode of the card number, in Code 39 like the plastic card (read by handheld scanners).
/// In `.vertical`, it reads top to bottom.
struct BarcodeView: View {
    let value: String
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    /// Wide/narrow ratio: 3 is the standard's maximum and the most forgiving to read.
    static let wideRatio = 3.0

    var body: some View {
        Canvas { context, size in
            guard let elements = Code39.elements(for: value) else { return }
            let isVertical = axis == .vertical
            let length = isVertical ? size.height : size.width
            let total = Code39.width(of: elements, wideRatio: Self.wideRatio)
            // Narrow module snapped to a whole number of pixels: crisp bars, no blur.
            let module = max(1, (length * displayScale / total).rounded(.down)) / displayScale
            var position = (length - module * total) / 2
            for element in elements {
                let width = module * (element.isWide ? Self.wideRatio : 1)
                if element.isBar {
                    let rect = isVertical
                        ? CGRect(x: 0, y: position, width: size.width, height: width)
                        : CGRect(x: position, y: 0, width: width, height: size.height)
                    context.fill(Path(rect), with: .color(.black))
                }
                position += width
            }
        }
        .accessibilityHidden(true)
    }
}

struct CardExpiryBanner: View {
    let patron: Patron

    var body: some View {
        Label(
            patron.cardExpired
                ? String.local("Votre carte a expiré. Renouvelez-la à l'accueil d'une médiathèque.")
                : String.local("Votre carte expire dans \(patron.cardExpiresInDays) jours. Renouvelez-la à l'accueil."),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(patron.cardExpired ? Color.statusDanger : Color.statusWarning)
        .cardStyle()
    }
}

// MARK: - Components

struct CounterTile: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.title.weight(.heavy)).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .cardStyle(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

struct MenuRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            accessory
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}
