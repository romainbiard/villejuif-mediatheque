import SwiftUI

// MARK: - Titre de section

/// Titre de section avec le trait violet de 4 pt au-dessus, motif repris du site.
public struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.brandViolet).frame(width: 28, height: 4)
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

// MARK: - Pastille de statut

public struct StatusPill: View {
    public enum Style: Sendable { case success, danger, warning, accent, neutral }

    let text: String
    let style: Style

    public init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var foreground: Color {
        switch style {
        case .success: .statusSuccess
        case .danger: .statusDanger
        case .warning: .statusWarning
        case .accent: .brandVioletDeep
        case .neutral: .inkSecondary
        }
    }

    private var background: Color {
        switch style {
        case .success: .soft(.statusSuccess)
        case .danger: .soft(.statusDanger)
        case .warning: Color.brandYellow.opacity(0.3)
        case .accent: .soft(.brandViolet)
        case .neutral: .soft(.inkSecondary)
        }
    }
}

// MARK: - Couverture

/// Jaquette du document, ou couverture générée aux couleurs de la charte si elle manque.
public struct CoverImage: View {
    let url: URL?
    let title: String
    let seed: Int

    public init(url: URL?, title: String, seed: Int) {
        self.url = url
        self.title = title
        self.seed = seed
    }

    public var body: some View {
        // Le cadre est fixé par l'appelant : l'image remplit ce cadre sans en déborder.
        Color.clear
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        GeneratedCover(title: title, seed: seed)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct GeneratedCover: View {
    let title: String
    let seed: Int

    var body: some View {
        let colors = BrandArtwork.colors(for: seed)
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                colors.background
                Circle()
                    .fill(colors.shape)
                    .frame(width: proxy.size.width * 1.1)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.45)
                if proxy.size.width > 80 {
                    Text(title)
                        .font(.system(size: proxy.size.width / 9, weight: .heavy))
                        .foregroundStyle(BrandArtwork.foreground(for: seed))
                        .lineLimit(3)
                        .padding(proxy.size.width / 12)
                }
            }
        }
    }
}

// MARK: - État vide

/// Composant d'état vide : pastille teintée, formes de la charte, titre, message et actions.
public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let tint: Color
    let primary: (label: String, action: () -> Void)?
    let secondary: (label: String, action: () -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = .brandViolet,
        primary: (label: String, action: () -> Void)? = nil,
        secondary: (label: String, action: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.primary = primary
        self.secondary = secondary
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.soft(tint)).frame(width: 96, height: 96)
                Circle().fill(Color.brandYellow).frame(width: 24).offset(x: 52, y: -44)
                Circle().fill(Color.brandMagenta).frame(width: 14).offset(x: -56, y: 42)
                Circle().stroke(Color.brandCyan, lineWidth: 3).frame(width: 10).offset(x: 48, y: 46)
                Image(systemName: systemImage).font(.system(size: 40, weight: .medium)).foregroundStyle(tint)
            }
            .frame(height: 120)
            .accessibilityHidden(true)

            Text(title).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)

            if let primary {
                Button(primary.label, action: primary.action)
                    .buttonStyle(.prominent(tint: tint, size: .large))
                    .padding(.top, 8)
            }
            if let secondary {
                Button(secondary.label, action: secondary.action).tint(tint)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Carte

public extension View {
    /// Carte pleine : le contenu reste opaque, le verre est réservé à la navigation.
    func cardStyle(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Squelette de chargement

public struct SkeletonRow: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).frame(width: 52, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 12)
            }
        }
        .foregroundStyle(Color.inkSecondary.opacity(0.15))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
