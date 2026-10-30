#if os(iOS)
import DesignSystem
import MediathequeCore
import StoreKit
import SwiftUI

/// Onglet Numérique : un lanceur des apps des fournisseurs, pas une copie de leur catalogue.
public struct DigitalView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = DigitalViewModel()
    @State private var helpOffer: DigitalOffer?
    @State private var appToInstall: ProviderApp?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Inclus dans votre abonnement, sur tous vos appareils.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                    banner
                    if let featured = viewModel.offers.first {
                        FeaturedOfferCard(
                            offer: featured,
                            isResolving: viewModel.resolving == featured.id,
                            open: { Task { await viewModel.open(featured) } },
                            help: { helpOffer = featured }
                        )
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(viewModel.offers.dropFirst()) { offer in
                            OfferTile(
                                offer: offer,
                                isResolving: viewModel.resolving == offer.id,
                                open: { Task { await viewModel.open(offer) } },
                                help: { helpOffer = offer }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Numérique")
            .sheet(item: $helpOffer) { offer in
                FirstUseSheet(offer: offer) { app in
                    helpOffer = nil
                    appToInstall = app
                }
            }
            .fullScreenCover(item: $viewModel.session) { session in
                PortalSheet(session: session)
            }
            .appStoreOverlay(isPresented: Binding(get: { appToInstall != nil }, set: { if !$0 { appToInstall = nil } })) {
                SKOverlay.AppConfiguration(appIdentifier: appToInstall?.appStoreID ?? "", position: .bottom)
            }
            .alert(
                "Ouverture impossible",
                isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in
            switch event {
            case .error: .error
            case .lightImpact: .impact(weight: .light)
            default: nil
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if session.patron == nil {
            Label("Connectez-vous dans l'onglet Compte pour ouvrir ces services.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandVioletDeep)
                .cardStyle()
        } else if session.patron?.permissions.digitalResourcesForbidden == true {
            Label("L'accès au numérique est suspendu sur votre compte. Renseignez-vous à l'accueil d'une médiathèque.", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.statusDanger)
                .cardStyle()
        }
    }
}

// MARK: - Cartes

struct FeaturedOfferCard: View {
    let offer: DigitalOffer
    let isResolving: Bool
    let open: () -> Void
    let help: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.category).font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.8)
            Text(offer.provider).font(.title.weight(.heavy))
            Text(offer.quota).font(.subheadline).opacity(0.85)
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Button(action: open) {
                    Group {
                        if isResolving {
                            ProgressView().tint(Color.ink)
                        } else {
                            Text(offer.app.map { "Ouvrir \($0.name)" } ?? "Ouvrir")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(Color(hex: 0x1C1B22))
                .controlSize(.large)
                Button("Première utilisation", systemImage: "questionmark", action: help)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
        .background {
            ZStack {
                Color(hex: 0x17161C)
                Circle().fill(Color.brandVioletDeep).frame(width: 300).offset(x: 150, y: -110)
                Circle().fill(Color.brandMagenta).frame(width: 130).offset(x: 120, y: -40)
                Image(systemName: "play.fill").font(.title).foregroundStyle(.white).offset(x: 120, y: -40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

struct OfferTile: View {
    let offer: DigitalOffer
    let isResolving: Bool
    let open: () -> Void
    let help: () -> Void

    var body: some View {
        let colors = BrandArtwork.colors(for: offer.colorSeed)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: offer.systemImage)
                    .font(.title3)
                    .foregroundStyle(BrandArtwork.foreground(for: offer.colorSeed))
                    .frame(width: 48, height: 48)
                    .background(colors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                Button("Première utilisation", systemImage: "questionmark.circle", action: help)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.category).font(.headline).foregroundStyle(Color.ink)
                Text("\(offer.provider) · \(offer.quota)")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: open) {
                Group {
                    if isResolving { ProgressView() } else { Text("Ouvrir") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.brandVioletDeep)
            .font(.subheadline.weight(.bold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Première utilisation

struct FirstUseSheet: View {
    let offer: DigitalOffer
    let install: (ProviderApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(offer.summary).foregroundStyle(Color.inkSecondary)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(offer.firstUseSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.brandViolet, in: Circle())
                                Text(step)
                            }
                        }
                    }
                    .cardStyle()

                    if let hint = offer.copyableHint {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.label).font(.footnote).foregroundStyle(Color.inkSecondary)
                                Text(hint.value).font(.title2.weight(.heavy)).monospacedDigit()
                            }
                            Spacer()
                            Button(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.string = hint.value
                                copied = true
                            }
                            .buttonStyle(.glass)
                        }
                        .cardStyle()
                    }

                    if let app = offer.app {
                        Button {
                            install(app)
                        } label: {
                            Label("Installer \(app.name)", systemImage: "arrow.down.app").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.brandViolet)
                        .controlSize(.large)
                    }

                    Button("Voir le tutoriel complet (PDF)") { openURL(offer.tutorialURL) }
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(offer.category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: copied)
    }
}

// MARK: - Session chez le fournisseur

struct PortalSheet: View {
    let session: PortalSession
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var handedOffToApp = false

    var body: some View {
        NavigationStack {
            PortalWebView(url: session.url, cookies: session.cookies, isLoading: $isLoading, handedOffToApp: $handedOffToApp)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if handedOffToApp {
                        VStack(spacing: 14) {
                            Image(systemName: "arrow.up.forward.app").font(.largeTitle).foregroundStyle(Color.brandViolet)
                            Text("Ouvert dans \(session.offer.app?.name ?? "l'app")").font(.title3.weight(.bold))
                            Button("Fermer") { dismiss() }.buttonStyle(.glassProminent).tint(.brandViolet)
                        }
                        .padding(28)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }
                .navigationTitle(session.offer.provider)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                    if isLoading { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
                }
        }
    }
}
#endif
