// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import SwiftUI

// MARK: - Primary button

/// Primary button in tinted glass, replacing `.glassProminent`:
/// - when disabled or busy, it keeps its color, faded, instead of the system grey;
/// - when busy, the text stays in place but hidden under the spinner, so the button does not change size.
public struct ProminentButtonStyle: ButtonStyle {
    public enum Size: Sendable {
        /// `compact`: in a list row or a card ("Installer", "Ouvrir").
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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Tint opacity when the button cannot be used (disabled or busy).
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
            // One line: a long label shrinks slightly instead of enlarging the button.
            // At accessibility text sizes it wraps instead (it would be cut off).
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
            .multilineTextAlignment(.center)
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
            .accessibilityValue(isLoading ? Text(.local("En cours", comment: "Accessibility value of a button while its action is loading")) :
                Text(verbatim: ""))
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    /// Brand guidelines primary button: purple by default, white text.
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
        Button {} label: { Text(verbatim: "Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent())
        Button {} label: { Text(verbatim: "Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent())
            .disabled(true)
        Button {} label: { Text(verbatim: "Se connecter").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent(isLoading: true))
            .disabled(true)
        Button {} label: { Text(verbatim: "Ouvrir Cafeyn").frame(maxWidth: .infinity) }
            .buttonStyle(.prominent(tint: .white, foreground: .ink, size: .large, isLoading: true))
    }
    .padding()
    .background(Color.surfaceGrouped)
}
