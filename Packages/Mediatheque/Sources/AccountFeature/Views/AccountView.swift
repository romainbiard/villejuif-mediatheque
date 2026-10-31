import DesignSystem
import MediathequeCore
import SearchFeature
import SwiftUI

/// Onglet Compte : connexion, ou accueil du compte une fois la session ouverte.
public struct AccountView: View {
    @Environment(SessionStore.self) private var session
    /// Passé à `true` (raccourci « Montrer ma carte ») : affiche la carte en grand, puis repasse à `false`.
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

/// Les 7 sections de Mon compte, pour la barre latérale de l'iPad.
public enum AccountSection: String, CaseIterable, Identifiable, Sendable {
    case loans, holds, selections, reviews, suggestions, information, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .loans: "Mes prêts"
        case .holds: "Mes réservations"
        case .selections: "Mes sélections"
        case .reviews: "Mes avis"
        case .suggestions: "Mes suggestions"
        case .information: "Mes informations"
        case .settings: "Mes configurations"
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

/// Une section de Mon compte ouverte seule (onglet de la barre latérale sur iPad).
/// Sans session, on affiche la connexion de l'onglet Compte.
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
    @State private var contentWidth: CGFloat = .infinity
    @AppStorage(ReminderSettings.Key.onboardingDone, store: .shared) private var onboardingDone = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if sizeClass == .regular && contentWidth >= Self.twoColumnsMinWidth {
                    // iPad : carte et compteurs à gauche, menu à droite.
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            cardAndCounters
                            logoutButton
                        }
                        .frame(maxWidth: 440)
                        menu
                    }
                    .frame(maxWidth: 1100)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        cardAndCounters
                        menu
                        logoutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Mon compte")
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
                        ? "Notifications, \(viewModel.unreadNotifications) non lue\(viewModel.unreadNotifications > 1 ? "s" : "")"
                        : "Notifications")
                }
            }
            .sheet(isPresented: $showsNotifications, onDismiss: viewModel.refreshUnreadCount) {
                NotificationsView {
                    showsNotifications = false
                    path.append(AccountRoute.settings)
                }
            }
            .refreshable { await viewModel.refresh(session) }
            .task { await viewModel.refresh(session) }
            .fullScreenCover(isPresented: $showsCard) { FullScreenCardView(patron: patron) }
            .onChange(of: cardRequest, initial: true) {
                guard cardRequest else { return }
                showsCard = true
                cardRequest = false
            }
            .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
                WelcomeSetupView(patron: patron) { onboardingDone = true }
            }
        }
        .measuringWidth($contentWidth)
        .sensoryFeedback(.impact(weight: .medium), trigger: session.state == .loggedOut)
    }

    /// Carte (440 pt), menu lisible (≥ 360 pt), marges et espacement.
    static let twoColumnsMinWidth: CGFloat = 880

    @ViewBuilder
    private var cardAndCounters: some View {
        if patron.cardExpired || patron.cardAboutToExpire {
            CardExpiryBanner(patron: patron)
        }
        Button { showsCard = true } label: { LibraryCardView(patron: patron) }
            .buttonStyle(.plain)
            .accessibilityHint("Affiche la carte en grand pour le comptoir")
        counters
    }

    private var logoutButton: some View {
        Button("Se déconnecter", role: .destructive) { confirmsLogout = true }
            // Attaché au bouton : sur iOS 26 la confirmation est un popover qui pointe vers sa vue.
            .confirmationDialog("Se déconnecter de votre compte ?", isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { Task { await session.logout() } }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private var counters: some View {
        HStack(spacing: 10) {
            NavigationLink(value: AccountRoute.loans) {
                CounterTile(value: patron.counters.loans, label: "Prêts", color: .ink)
            }
            NavigationLink(value: AccountRoute.loans) {
                CounterTile(value: patron.counters.lateLoans, label: "En retard", color: .statusDanger)
            }
            NavigationLink(value: AccountRoute.holds) {
                CounterTile(value: patron.counters.waitingToBePulled, label: "À retirer", color: .statusSuccess)
            }
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Mes emprunts")
            VStack(spacing: 0) {
                NavigationLink(value: AccountRoute.loans) {
                    MenuRow(title: "Mes prêts", systemImage: "books.vertical.fill", tint: .brandViolet) {
                        if patron.counters.lateLoans > 0 {
                            StatusPill("\(patron.counters.lateLoans) en retard", style: .danger)
                        }
                    }
                }
                Divider().padding(.leading, 58)
                NavigationLink(value: AccountRoute.holds) {
                    MenuRow(title: "Mes réservations", systemImage: "bookmark.fill", tint: .statusSuccess) {
                        if patron.counters.waitingToBePulled > 0 {
                            StatusPill("\(patron.counters.waitingToBePulled) à retirer", style: .success)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 0)

            SectionHeader("Mes listes").padding(.top, 10)
            VStack(spacing: 0) {
                menuLink(.selections, "Mes sélections", "heart.fill", .brandMagenta)
                Divider().padding(.leading, 58)
                menuLink(.reviews, "Mes avis", "star.fill", .statusWarning)
                Divider().padding(.leading, 58)
                menuLink(.suggestions, "Mes suggestions d'achat", "lightbulb.fill", .brandVioletDeep)
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 0)

            SectionHeader("Mon profil").padding(.top, 10)
            VStack(spacing: 0) {
                menuLink(.information, "Mes informations", "person.text.rectangle.fill", .ink)
                Divider().padding(.leading, 58)
                menuLink(.settings, "Mes configurations", "gearshape.fill", .inkSecondary)
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

// MARK: - Carte d'abonné

struct LibraryCardView: View {
    let patron: Patron

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    VillejuifLogo.white.resizable().scaledToFit().frame(height: 26).accessibilityLabel("Ville de Villejuif")
                    Text(patron.displayName).font(.title2.weight(.bold))
                    if let expiry = patron.cardExpiry {
                        Text("Carte valable jusqu'au \(expiry.formatted(.dateTime.day().month(.wide).year()))")
                            .font(.footnote)
                            .opacity(0.85)
                    }
                }
                Spacer()
                Text("Gratuit")
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
                    Text("Toucher pour agrandir").font(.footnote).foregroundStyle(Color(hex: 0x5E5B66))
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
        .accessibilityLabel("Carte d'abonné de \(patron.displayName), numéro \(patron.cardNumber)")
    }
}

/// Carte plein écran pour le comptoir, luminosité au maximum le temps de l'affichage.
struct FullScreenCardView: View {
    let patron: Patron
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(patron.displayName).font(.title.weight(.bold))
            BarcodeView(value: patron.cardNumber).frame(height: 140).padding(.horizontal, 24)
            Text(patron.cardNumber).font(.title2.weight(.semibold)).monospacedDigit().tracking(4)
            Spacer()
            Button("Fermer") { dismiss() }.buttonStyle(.glass).controlSize(.large)
        }
        .foregroundStyle(Color(hex: 0x1C1B22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .onAppear(perform: brighten)
        .onDisappear(perform: restore)
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

/// Code-barres du numéro de carte, en Code 39 comme sur la carte en plastique (lu par les douchettes).
struct BarcodeView: View {
    let value: String
    @Environment(\.displayScale) private var displayScale

    /// Rapport large/étroit : 3 est le maximum de la norme et le plus tolérant à la lecture.
    static let wideRatio = 3.0

    var body: some View {
        Canvas { context, size in
            guard let elements = Code39.elements(for: value) else { return }
            let total = Code39.width(of: elements, wideRatio: Self.wideRatio)
            // Module étroit calé sur un nombre entier de pixels : des barres nettes, sans flou.
            let module = max(1, (size.width * displayScale / total).rounded(.down)) / displayScale
            var x = ((size.width - module * total) / 2)
            for element in elements {
                let width = module * (element.isWide ? Self.wideRatio : 1)
                if element.isBar {
                    context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(.black))
                }
                x += width
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
                ? "Votre carte a expiré. Renouvelez-la à l'accueil d'une médiathèque."
                : "Votre carte expire dans \(patron.cardExpiresInDays) jours. Renouvelez-la à l'accueil.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(patron.cardExpired ? Color.statusDanger : Color.statusWarning)
        .cardStyle()
    }
}

// MARK: - Éléments

struct CounterTile: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title.weight(.heavy)).foregroundStyle(color)
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
