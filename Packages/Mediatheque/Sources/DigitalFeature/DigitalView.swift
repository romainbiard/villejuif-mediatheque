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

#endif
