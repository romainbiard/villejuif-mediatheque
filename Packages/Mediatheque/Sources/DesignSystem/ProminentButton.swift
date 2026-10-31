import SwiftUI

// MARK: - Bouton principal

/// Bouton principal en verre teinté, à la place de `.glassProminent` :
/// - désactivé ou en cours, il garde sa couleur, estompée, au lieu du gris système ;
/// - en cours, le texte reste en place mais invisible sous le spinner, pour que le bouton ne change pas de taille.
public struct ProminentButtonStyle: ButtonStyle {
    public enum Size: Sendable {
        /// `compact` : dans une ligne de liste ou une carte (« Installer », « Ouvrir »).
        case compact, large, extraLarge

        var minHeight: CGFloat {
            switch self {
            case .compact: 34
            case .large: 50
            case .extraLarge: 56
            }
        }

        var font: Font {
            switch self {
            case .compact: .subheadline.weight(.bold)
            case .large: .body.weight(.semibold)
            case .extraLarge: .headline
            }
        }

        var horizontalPadding: CGFloat { self == .compact ? 14 : 20 }
    }

    let tint: Color
    let foreground: Color
    let size: Size
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled

    /// Opacité de la teinte quand le bouton ne peut pas servir (désactivé ou en cours).
    static let fadedOpacity = 0.45

    public init(tint: Color, foreground: Color, size: Size, isLoading: Bool) {
        self.tint = tint
        self.foreground = foreground
        self.size = size
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isActive = isEnabled && !isLoading
        configuration.label
            .font(size.font)
            // Toujours une ligne : un libellé long rétrécit un peu au lieu de grandir le bouton.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foreground)
            .opacity(isLoading ? 0 : isActive ? 1 : 0.8)
            .overlay {
                if isLoading { ProgressView().tint(foreground) }
            }
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
            .contentShape(Capsule())
            .glassEffect(
                .regular.tint(tint.opacity(isActive ? 1 : Self.fadedOpacity)).interactive(isActive),
                in: Capsule()
            )
            .animation(.easeOut(duration: 0.2), value: isActive)
            .accessibilityValue(isLoading ? Text("En cours") : Text(""))
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    /// Bouton principal de la charte : violet par défaut, texte blanc.
    public static func prominent(
        tint: Color = .brandViolet,
        foreground: Color = .white,
        size: ProminentButtonStyle.Size = .extraLarge,
        isLoading: Bool = false
    ) -> ProminentButtonStyle {
        ProminentButtonStyle(tint: tint, foreground: foreground, size: size, isLoading: isLoading)
    }
}

#Preview("États") {
    VStack(spacing: 16) {
        Button {} label: { Text("Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent())
        Button {} label: { Text("Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent())
            .disabled(true)
        Button {} label: { Text("Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent(isLoading: true))
            .disabled(true)
        Button {} label: { Text("Ouvrir Cafeyn").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent(tint: .white, foreground: .ink, size: .large, isLoading: true))
    }
    .padding()
    .background(Color.surfaceGrouped)
}
