// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import SwiftUI

/// The city's brand guidelines, taken from `skins/villejuif/CSS/villejuif_2026.css` and the logo.
public extension Color {
    /// The website's `--rose`: main accent (buttons, active tab, account header).
    static let brandViolet = Color(light: 0x773DBD, dark: 0xAE8BE6, highContrastLight: 0x5E2A9E, highContrastDark: 0xC9AEF0)
    /// Brand purple as a surface under white text (cards, sign-in, lock screen): the same in both
    /// modes. The lighter dark-mode `brandViolet` only reaches 3.3:1 with white; this one 6.6:1.
    static let brandVioletSurface = Color(hex: 0x773DBD)
    /// `--falu_red`, the logo color: city identity, highlights.
    static let brandMagenta = Color(light: 0xE0005A, dark: 0xFF4D8D)
    static let brandVioletDeep = Color(light: 0x5714A4, dark: 0xC9B0F2)
    static let brandCyan = Color(hex: 0x84DADE)
    static let brandYellow = Color(hex: 0xFEDC1B)

    static let statusSuccess = Color(light: 0x006E43, dark: 0x4CC38A, highContrastLight: 0x005434, highContrastDark: 0x86DDB1)
    static let statusDanger = Color(light: 0xA60A3D, dark: 0xFF6B8E, highContrastLight: 0x84002D, highContrastDark: 0xFF9AB2)
    static let statusWarning = Color(light: 0x7A4F00, dark: 0xF5C451, highContrastLight: 0x5C3B00, highContrastDark: 0xFFDB8A)

    static let ink = Color(light: 0x1C1B22, dark: 0xF4F3F8)
    /// Glyph on a tinted tile: white on the light-mode tints, dark on the dark-mode ones,
    /// which turn light (white on them drops to 1.1–2.2:1).
    static let onTint = Color(light: 0xFFFFFF, dark: 0x1C1B22)
    static let inkSecondary = Color(light: 0x5E5B66, dark: 0xB4B1BE, highContrastLight: 0x3F3C46, highContrastDark: 0xDAD8E2)
    static let surfaceGrouped = Color(light: 0xF4F3F8, dark: 0x0F0E13)
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x1C1B22)

    /// Pale background paired with a status color (badges).
    static func soft(_ color: Color) -> Color { color.opacity(0.14) }
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// `highContrastLight` and `highContrastDark` are used when "Increase Contrast" is on (Settings › Accessibility).
    init(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let hex = switch (isDark, isHighContrast) {
            case (false, false): light
            case (true, false): dark
            case (false, true): highContrastLight ?? light
            case (true, true): highContrastDark ?? dark
            }
            return UIColor(Color(hex: hex))
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #endif
    }
}

/// Category colors for generated covers and posters.
public enum BrandArtwork {
    public static let palette: [(background: Color, shape: Color)] = [
        (.brandViolet, .brandMagenta),
        (.brandYellow, .brandMagenta),
        (.brandCyan, .brandVioletDeep),
        (.brandVioletDeep, .brandCyan),
        (Color(hex: 0xA60A3D), .brandYellow),
        (Color(hex: 0x1C1B22), .brandMagenta)
    ]

    /// Stable colors for a given identifier.
    public static func colors(for seed: Int) -> (background: Color, shape: Color) {
        palette[abs(seed) % palette.count]
    }

    /// Text color on the `colors(for:)` background: dark on yellow and cyan, white elsewhere.
    public static func foreground(for seed: Int) -> Color {
        [1, 2].contains(abs(seed) % palette.count) ? Color(hex: 0x1C1B22) : .white
    }
}

/// City logo (files from the library website). Its use in the app remains subject to the city's approval.
public enum VillejuifLogo {
    public static let white = Image("villejuif-logo-white", bundle: .module)
    /// Coat of arms alone, without the word "VILLEJUIF" (app icon, notification previews). Template image: can be tinted.
    public static let crest = Image("villejuif-crest", bundle: .module)
}
