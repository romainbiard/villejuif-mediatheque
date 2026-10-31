import Foundation

/// Code 39 (« 3 parmi 9 »), la symbologie imprimée sur les cartes d'abonné des médiathèques
/// (relevé sur une carte le 31/10/2026 : 7 chiffres, sans caractère de contrôle).
/// CoreImage ne sait générer que du Code 128, d'où cet encodeur.
public enum Code39 {
    /// Un module du code-barres : barre ou espace, étroit ou large.
    public struct Element: Hashable, Sendable {
        public let isBar: Bool
        public let isWide: Bool
    }

    /// Les 9 éléments de chaque caractère, barre en premier : `n` étroit, `w` large.
    static let patterns: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw", "3": "wnwwnnnnn",
        "4": "nnnwwnnnw", "5": "wnnwwnnnn", "6": "nnwwwnnnn", "7": "nnnwnnwnw",
        "8": "wnnwnnwnn", "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn", "D": "nnnnwwnnw",
        "E": "wnnnwwnnn", "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn",
        "I": "nnwnnwwnn", "J": "nnnnwwwnn", "K": "wnnnnnnww", "L": "nnwnnnnww",
        "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn", "P": "nnwnwnnwn",
        "Q": "nnnnnnwww", "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw",
        "Y": "wwnnwnnnn", "Z": "nwwnwnnnn",
        "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn", "$": "nwnwnwnnn",
        "/": "nwnwnnnwn", "+": "nwnnnwnwn", "%": "nnnwnwnwn", "*": "nwnnwnwnn",
    ]

    /// Éléments de `value` encadrée par les `*` de début et de fin, avec un espace étroit
    /// entre deux caractères. `nil` si un caractère n'existe pas en Code 39.
    public static func elements(for value: String) -> [Element]? {
        let characters = Array("*\(value.uppercased())*")
        var elements: [Element] = []
        for (index, character) in characters.enumerated() {
            guard let pattern = patterns[character], character != "*" || index == 0 || index == characters.count - 1 else {
                return nil
            }
            for (position, width) in pattern.enumerated() {
                elements.append(Element(isBar: position.isMultiple(of: 2), isWide: width == "w"))
            }
            if index < characters.count - 1 {
                elements.append(Element(isBar: false, isWide: false))
            }
        }
        return elements
    }

    /// Largeur totale en modules étroits, pour un rapport large/étroit donné.
    public static func width(of elements: [Element], wideRatio: Double) -> Double {
        elements.reduce(0) { $0 + ($1.isWide ? wideRatio : 1) }
    }
}
