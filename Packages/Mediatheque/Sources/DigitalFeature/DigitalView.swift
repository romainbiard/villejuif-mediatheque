// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import DesignSystem
import MediathequeCore
import StoreKit
import SwiftUI

/// Digital tab: a launcher for the providers' apps, not a copy of their catalog.
public struct DigitalView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = DigitalViewModel()
    @State private var helpOffer: DigitalOffer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Width of the scroll content, padding included (0 until the first layout pass).
    @State private var contentWidth: CGFloat = 0

    public init() {}

    @Environment(\.openURL) private var openURL

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(.local("Inclus dans votre abonnement, sur tous vos appareils."))
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                    banner
                    // At accessibility text sizes, one column everywhere (iPad mosaic included):
                    // two or three columns would break words in the middle.
                    if sizeClass == .regular, !typeSize.isAccessibilitySize {
                        mosaic
                    } else {
                        if let featured = viewModel.offers.first { featuredCard(featured) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                            ForEach(viewModel.offers.dropFirst()) { tile($0) }
                        }
                    }
                }
                .frame(maxWidth: sizeClass == .regular ? Self.mosaicMaxWidth : nil, alignment: .leading)
                .padding(.horizontal, sizeClass == .regular ? 24 : 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(.local("Numérique"))
            // The App Store sheet is shown once the sheet has closed: never present over a sheet that is going away.
            .sheet(item: $helpOffer, onDismiss: presentStoreIfNeeded) { offer in
                HowItWorksSheet(
                    offer: offer,
                    availability: offer.app.map { viewModel.availability(of: $0) } ?? .unknown,
                    primaryLabel: primaryLabel(for: offer, compact: false),
                    primary: {
                        helpOffer = nil
                        Task { await viewModel.primaryAction(offer) }
                    },
                    install: {
                        helpOffer = nil
                        viewModel.getApp(for: offer)
                    }
                )
            }
            .sheet(item: $viewModel.installOffer, onDismiss: presentStoreIfNeeded) { offer in
                if let app = offer.app {
                    InstallAppSheet(
                        offer: offer,
                        app: app,
                        get: { viewModel.getApp(for: offer) },
                        continueOnWeb: { Task { await viewModel.continueOnWeb(offer) } }
                    )
                }
            }
            .fullScreenCover(item: $viewModel.session) { session in
                PortalSheet(session: session)
            }
            .overlay(alignment: .bottom) { installedBanner }
            .task { await viewModel.refreshInstalledApps() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await viewModel.refreshInstalledApps() } }
            }
            .alert(
                .local("Ouverture impossible"),
                isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } })
            ) {
                Button(.local("OK"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in
            switch event {
            case .success: .success
            case .error: .error
            case .lightImpact: .impact(weight: .light)
            default: nil
            }
        }
    }

    // MARK: Layout

    /// iPad: three columns from this width (the detail column of an 11-inch iPad in landscape,
    /// next to the sidebar, is about 830 pt), two below (portrait, narrow window).
    static let threeColumnsMinWidth: CGFloat = 700
    static let mosaicMaxWidth: CGFloat = 1000

    /// iPad mosaic: Films over two columns (the whole width on two columns), the other services
    /// as tiles, and the last one (Eurêka and musicMe) as a horizontal banner. Every service fits
    /// on one 11-inch screen, and buttons keep the width of their label.
    private var mosaic: some View {
        let columns = contentWidth >= Self.threeColumnsMinWidth ? 3 : 2
        let offers = viewModel.offers
        let featured = offers.first
        let last = offers.count > 2 ? offers.last : nil
        let tiles = Array(offers.dropFirst().dropLast(last == nil ? 0 : 1))
        // With three columns, the first tile sits next to Films.
        let besideFeatured = columns == 3 ? Array(tiles.prefix(1)) : []
        let rows = Array(tiles.dropFirst(besideFeatured.count)).chunked(into: columns)
        // Explicit widths: a `Grid` sizes its columns to the ideal width of long texts and overflows.
        let spacing: CGFloat = 16
        let inner = min(contentWidth - 48, Self.mosaicMaxWidth)
        let column = max(0, (inner - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return VStack(alignment: .leading, spacing: spacing) {
            if let featured {
                HStack(alignment: .top, spacing: spacing) {
                    featuredCard(featured, fitsLabel: true)
                        .frame(width: column * 2 + spacing)
                    ForEach(besideFeatured) { tile($0, isPad: true).frame(width: column) }
                }
                // Same height for every card of the row.
                .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[index]) { tile($0, isPad: true).frame(width: column) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let last {
                OfferBanner(
                    offer: last,
                    access: viewModel.access(for: last),
                    primaryLabel: primaryLabel(for: last, compact: true),
                    needsInstall: viewModel.needsInstall(last),
                    isResolving: viewModel.resolving == last.id,
                    open: { Task { await viewModel.primaryAction(last) } },
                    menu: menuActions(for: last)
                )
            }
        }
    }

    private func featuredCard(_ offer: DigitalOffer, fitsLabel: Bool = false) -> some View {
        FeaturedOfferCard(
            offer: offer,
            access: viewModel.access(for: offer),
            primaryLabel: primaryLabel(for: offer, compact: false),
            needsInstall: viewModel.needsInstall(offer),
            isResolving: viewModel.resolving == offer.id,
            fitsLabel: fitsLabel,
            open: { Task { await viewModel.primaryAction(offer) } },
            menu: menuActions(for: offer)
        )
    }

    private func tile(_ offer: DigitalOffer, isPad: Bool = false) -> some View {
        OfferTile(
            offer: offer,
            access: viewModel.access(for: offer),
            primaryLabel: primaryLabel(for: offer, compact: true),
            needsInstall: viewModel.needsInstall(offer),
            isResolving: viewModel.resolving == offer.id,
            isPad: isPad,
            open: { Task { await viewModel.primaryAction(offer) } },
            menu: menuActions(for: offer)
        )
    }

    private func primaryLabel(for offer: DigitalOffer, compact: Bool) -> String {
        if viewModel.needsInstall(offer) { return compact ? .local("Installer") : .local("Installer l'app") }
        if !compact, viewModel.access(for: offer) == .appInstalled, let app = offer.app { return .local("Ouvrir \(app.name)") }
        return offer.webActionLabel
    }

    private func menuActions(for offer: DigitalOffer) -> ServiceMenu.Actions {
        ServiceMenu.Actions(
            connect: viewModel.canConnectApp(offer) ? { Task { await viewModel.connectThroughPortal(offer) } } : nil,
            // For a required app, the web is the alternative; elsewhere, it is already the primary button.
            web: offer.app?.role == .required ? { Task { await viewModel.continueOnWeb(offer) } } : nil,
            howItWorks: { helpOffer = offer },
            tutorial: { openURL(offer.tutorialURL) }
        )
    }

    private func presentStoreIfNeeded() {
        guard let product = viewModel.storeProduct else { return }
        AppStorePresenter.present(appStoreID: product.id) {
            Task { await viewModel.storeDismissed() }
        }
    }

    /// "L'app est installée": sign-in starts on its own when returning from the App Store.
    @ViewBuilder
    private var installedBanner: some View {
        if let id = viewModel.justInstalled, let offer = viewModel.offers.first(where: { $0.id == id }), let app = offer.app {
            HStack(spacing: 12) {
                Image(systemName: offer.systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x17161C), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(.local("\(app.name) est installée")).font(.subheadline.weight(.bold))
                    Text(.local("Connexion avec votre carte…")).font(.footnote).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .task(id: id) {
                AccessibilityNotification.Announcement(String.local("\(app.name) est installée")).post()
                try? await Task.sleep(for: .seconds(4))
                withAnimation { viewModel.dismissInstalledBanner() }
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if session.patron == nil {
            Label(.local("Connectez-vous dans l'onglet Compte pour ouvrir ces services."), systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandVioletDeep)
                .cardStyle()
        } else if session.patron?.permissions.digitalResourcesForbidden == true {
            Label(
                .local("L'accès au numérique est suspendu sur votre compte. Renseignez-vous à l'accueil d'une médiathèque."),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.statusDanger)
            .cardStyle()
        }
    }
}

private extension Array {
    /// Rows of the mosaic: `[a, b, c, d]` in rows of 3 → `[[a, b, c], [d]]`.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Cards

/// "Where it is used" line, under the service name.
struct AccessLine: View {
    let access: ServiceAccess
    var onDark = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        switch access {
        case .appInstalled:
            Label(.local("App installée"), systemImage: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(onDark ? Color.brandCyan : Color(light: 0x0B6B70, dark: 0x84DADE))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        case .inApp: plain(.local("Se consulte dans l'app"))
        case let .reader(app): plain(.local("À lire dans \(app)"))
        case .web: plain(.local("Sur le web"))
        }
    }

    private func plain(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }
}

/// A service's "…" button: the secondary actions, replacing the old "?" help.
struct ServiceMenu: View {
    struct Actions {
        /// Only when the app is installed: (re)connection through the portal.
        var connect: (() -> Void)?
        var web: (() -> Void)?
        var howItWorks: () -> Void
        var tutorial: () -> Void
    }

    let title: String
    let actions: Actions
    var large = false

    var body: some View {
        Menu {
            if let connect = actions.connect {
                Button(.local("Connecter l'app avec ma carte"), systemImage: "person.badge.key", action: connect)
            }
            if let web = actions.web {
                Button(.local("Ouvrir sur le web"), systemImage: "safari", action: web)
            }
            Section {
                Button(.local("Comment ça marche"), systemImage: "questionmark.circle", action: actions.howItWorks)
                Button(.local("Tutoriel complet (PDF)"), systemImage: "doc.text", action: actions.tutorial)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font((large ? Font.body : .subheadline).weight(.bold))
                .foregroundStyle(large ? Color.white : Color.brandVioletDeep)
                .frame(width: large ? 50 : 32, height: large ? 50 : 32)
                .background(large ? Color(hex: 0x5714A4) : Color.brandViolet.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(.local("Plus d'options pour \(title)"))
    }
}

struct FeaturedOfferCard: View {
    let offer: DigitalOffer
    let access: ServiceAccess
    let primaryLabel: String
    let needsInstall: Bool
    let isResolving: Bool
    /// iPad: the button keeps the width of its label and the service description shows.
    var fitsLabel = false
    let open: () -> Void
    let menu: ServiceMenu.Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Space reserved to the right of the text for the play circle (104 pt + margins).
    static let artworkWidth: CGFloat = 116

    var body: some View {
        // At accessibility text sizes the artwork goes away so the text gets the full width,
        // and the menu moves under the button.
        let showsArtwork = !typeSize.isAccessibilitySize
        let actions = showsArtwork
            ? AnyLayout(HStackLayout(spacing: 10))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 10))
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(offer.category).font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.8)
                Text(offer.provider).font(.title.weight(.heavy))
                Text(fitsLabel ? "\(offer.summary) · \(offer.quota)" : offer.quota)
                    .font(.subheadline)
                    .opacity(0.85)
                    .lineLimit(fitsLabel ? 3 : nil)
                if access == .appInstalled {
                    AccessLine(access: access, onDark: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.brandCyan.opacity(0.18), in: Capsule())
                        .padding(.top, 2)
                }
            }
            // The text stops before the play circle, whatever the card width.
            .padding(.trailing, showsArtwork ? Self.artworkWidth : 0)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            actions {
                Button(action: open) {
                    Group {
                        if needsInstall {
                            Label(primaryLabel, systemImage: "arrow.down")
                        } else {
                            Text(primaryLabel)
                        }
                    }
                    .frame(maxWidth: fitsLabel ? nil : .infinity)
                }
                .buttonStyle(.prominent(tint: .white, foreground: Color(hex: 0x1C1B22), size: .large, isLoading: isResolving))
                .disabled(isResolving)
                .fixedSize(horizontal: fitsLabel, vertical: false)
                ServiceMenu(title: offer.provider, actions: menu, large: true)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: fitsLabel ? .infinity : nil, alignment: .leading)
        .background {
            // Decoration pinned to the top-right corner (not the center): it no longer slides
            // under the title when the card widens (iPad, unfolded iPhone Duo).
            ZStack(alignment: .topTrailing) {
                Color(hex: 0x17161C)
                if showsArtwork {
                    Circle().fill(Color.brandVioletDeep).frame(width: 260).offset(x: 110, y: -130)
                    ZStack {
                        Circle().fill(Color.brandMagenta)
                        Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                    }
                    .frame(width: 104, height: 104)
                    .padding([.top, .trailing], 20)
                }
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

struct OfferTile: View {
    let offer: DigitalOffer
    let access: ServiceAccess
    let primaryLabel: String
    let needsInstall: Bool
    let isResolving: Bool
    /// iPad: description shown, access line and button on the same bottom row.
    var isPad = false
    let open: () -> Void
    let menu: ServiceMenu.Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let colors = BrandArtwork.colors(for: offer.colorSeed)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: offer.systemImage)
                    .font(.title3)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(BrandArtwork.foreground(for: offer.colorSeed))
                    .frame(width: 48, height: 48)
                    .background(colors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                ServiceMenu(title: offer.category, actions: menu)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.category).font(.headline).foregroundStyle(Color.ink)
                Text(verbatim: "\(offer.provider) · \(offer.quota)")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                AccessLine(access: access).padding(.top, 2)
                if isPad {
                    Text(offer.summary)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if isPad {
                // Button alone at the bottom, the width of its label.
                HStack {
                    Spacer(minLength: 0)
                    TileButton(label: primaryLabel, access: access, needsInstall: needsInstall, isResolving: isResolving, fillsWidth: false, action: open)
                }
            } else {
                TileButton(label: primaryLabel, access: access, needsInstall: needsInstall, isResolving: isResolving, fillsWidth: true, action: open)
            }
        }
        .padding(isPad ? 16 : 14)
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: isPad ? .infinity : nil, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: isPad ? 26 : 24, style: .continuous))
    }
}

/// Last service on iPad (Eurêka and musicMe): a horizontal banner across the whole mosaic.
struct OfferBanner: View {
    let offer: DigitalOffer
    let access: ServiceAccess
    let primaryLabel: String
    let needsInstall: Bool
    let isResolving: Bool
    let open: () -> Void
    let menu: ServiceMenu.Actions

    var body: some View {
        let colors = BrandArtwork.colors(for: offer.colorSeed)
        HStack(spacing: 16) {
            Image(systemName: offer.systemImage)
                .font(.title3)
                .foregroundStyle(BrandArtwork.foreground(for: offer.colorSeed))
                .frame(width: 52, height: 52)
                .background(colors.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.category).font(.headline).foregroundStyle(Color.ink)
                Text(verbatim: "\(offer.provider) · \(offer.summary)")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            AccessLine(access: access)
            TileButton(label: primaryLabel, access: access, needsInstall: needsInstall, isResolving: isResolving, fillsWidth: false, action: open)
            ServiceMenu(title: offer.category, actions: menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Button of a service tile: filled when the app is present, light purple to install, neutral for the web.
struct TileButton: View {
    let label: String
    let access: ServiceAccess
    let needsInstall: Bool
    let isResolving: Bool
    /// iPhone: across the tile; iPad: the width of the label.
    let fillsWidth: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isResolving {
                    ProgressView()
                } else if needsInstall {
                    Label(label, systemImage: "arrow.down")
                } else {
                    Text(label)
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, fillsWidth ? 0 : 18)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 36)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isResolving)
        .fixedSize(horizontal: !fillsWidth, vertical: false)
    }

    private var background: Color {
        if access == .appInstalled { return .brandVioletDeep }
        if needsInstall { return .brandViolet.opacity(0.14) }
        return Color.surfaceGrouped
    }

    private var foreground: Color {
        if access == .appInstalled { return Color(light: 0xFFFFFF, dark: 0x1C1B22) }
        if needsInstall { return .brandVioletDeep }
        return .ink
    }
}

// MARK: - How it works

struct HowItWorksSheet: View {
    let offer: DigitalOffer
    let availability: AppAvailability
    let primaryLabel: String
    let primary: () -> Void
    let install: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Text(offer.summary).foregroundStyle(Color.inkSecondary)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(offer.firstUseSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: "\(index + 1)")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.brandViolet, in: Circle())
                                Text(step)
                            }
                        }
                    }

                    if let hint = offer.copyableHint {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.label).font(.footnote).foregroundStyle(Color.inkSecondary)
                                Text(hint.value).font(.title2.weight(.heavy)).monospacedDigit()
                            }
                            Spacer()
                            Button(copied ? LocalizedStringResource.local("Copié") : .local("Copier"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.string = hint.value
                                copied = true
                            }
                            .buttonStyle(.prominent(tint: .brandViolet.opacity(0.14), foreground: .brandVioletDeep))
                            .fixedSize()
                        }
                        .cardStyle()
                    }

                    // Companion app (reader, music, comics): installed or to install, here.
                    if let app = offer.app, app.role != .required {
                        companionRow(app)
                    }

                    Button(action: primary) {
                        Text(primaryLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.prominent(size: .large))

                    Button(.local("Tutoriel complet (PDF)")) { openURL(offer.tutorialURL) }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Color.surfaceGrouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.local("Fermer"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: copied)
    }

    private var header: some View {
        HStack(spacing: 12) {
            let colors = BrandArtwork.colors(for: offer.colorSeed)
            Image(systemName: offer.systemImage)
                .font(.title3)
                .foregroundStyle(BrandArtwork.foreground(for: offer.colorSeed))
                .frame(width: 48, height: 48)
                .background(colors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.category).font(.footnote.weight(.bold)).textCase(.uppercase).foregroundStyle(Color.inkSecondary)
                Text(.local("Comment ça marche")).font(.title2.weight(.heavy))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func companionRow(_ app: ProviderApp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hex: 0x1C1B22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.subheadline.weight(.bold))
                Text(.local("\(app.publisher) · Gratuite")).font(.footnote).foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
            if availability == .installed, let url = app.launchURL {
                Button(.local("Ouvrir")) { openURL(url) }
                    .buttonStyle(.prominent(size: .compact))
                    .fixedSize()
            } else {
                Button(.local("Installer"), action: install)
                    .buttonStyle(.prominent(size: .compact))
                    .fixedSize()
            }
        }
        .cardStyle()
    }
}

// MARK: - Session with the provider

struct PortalSheet: View {
    let session: PortalSession
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var handedOffToApp = false

    private var appName: String { session.offer.app?.name ?? .local("l'app") }

    var body: some View {
        NavigationStack {
            PortalWebView(url: session.url, cookies: session.cookies, isLoading: $isLoading, handedOffToApp: $handedOffToApp)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if handedOffToApp {
                        VStack(spacing: 14) {
                            Image(systemName: "arrow.up.forward.app").font(.largeTitle).foregroundStyle(Color.brandViolet)
                            Text(.local("Ouvert dans \(appName)")).font(.title3.weight(.bold))
                            Button(.local("Fermer")) { dismiss() }.buttonStyle(.prominent(size: .large))
                        }
                        .padding(28)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }
                .navigationTitle(session.offer.provider)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(.local("Fermer")) { dismiss() } }
                    if isLoading { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
                }
        }
    }
}
#endif
