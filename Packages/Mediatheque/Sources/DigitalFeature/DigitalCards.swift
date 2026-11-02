// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if os(iOS)
import DesignSystem
import SwiftUI

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
#endif
