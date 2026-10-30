import SwiftUI

/// Charte de la ville, relevée dans `skins/villejuif/CSS/villejuif_2026.css` et sur le logo.
public extension Color {
    /// `--rose` du site : accent principal (boutons, onglet actif, en-tête du compte).
    static let brandViolet = Color(light: 0x773DBD, dark: 0xA27BE0)
    /// `--falu_red`, couleur du logo : identité ville, temps forts.
    static let brandMagenta = Color(light: 0xE0005A, dark: 0xFF4D8D)
    static let brandVioletDeep = Color(light: 0x5714A4, dark: 0xC9B0F2)
    static let brandCyan = Color(hex: 0x84DADE)
    static let brandYellow = Color(hex: 0xFEDC1B)

    static let statusSuccess = Color(light: 0x006E43, dark: 0x4CC38A)
    static let statusDanger = Color(light: 0xA60A3D, dark: 0xFF6B8E)
    static let statusWarning = Color(light: 0x7A4F00, dark: 0xF5C451)

    static let ink = Color(light: 0x1C1B22, dark: 0xF4F3F8)
    static let inkSecondary = Color(light: 0x5E5B66, dark: 0xB4B1BE)
    static let surfaceGrouped = Color(light: 0xF4F3F8, dark: 0x0F0E13)
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x1C1B22)

    /// Fond pâle associé à une couleur de statut (pastilles).
    static func soft(_ color: Color) -> Color { color.opacity(0.14) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #endif
    }
}

/// Couleurs de catégorie pour les couvertures et affiches générées.
public enum BrandArtwork {
    public static let palette: [(background: Color, shape: Color)] = [
        (.brandViolet, .brandMagenta),
        (.brandYellow, .brandMagenta),
        (.brandCyan, .brandVioletDeep),
        (.brandVioletDeep, .brandCyan),
        (Color(hex: 0xA60A3D), .brandYellow),
        (Color(hex: 0x1C1B22), .brandMagenta),
    ]

    /// Couleurs stables pour un identifiant donné.
    public static func colors(for seed: Int) -> (background: Color, shape: Color) {
        palette[abs(seed) % palette.count]
    }

    /// Couleur du texte posé sur le fond de `colors(for:)` : sombre sur jaune et cyan, blanc ailleurs.
    public static func foreground(for seed: Int) -> Color {
        [1, 2].contains(abs(seed) % palette.count) ? Color(hex: 0x1C1B22) : .white
    }
}
