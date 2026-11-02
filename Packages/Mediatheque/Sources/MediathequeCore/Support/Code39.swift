// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Code 39 ("3 of 9"), the symbology printed on the libraries' library cards
/// (checked on a card on 31/10/2026: 7 digits, no check character).
/// CoreImage can only generate Code 128, hence this encoder.
public enum Code39 {
    /// One barcode module: bar or space, narrow or wide.
    public struct Element: Hashable, Sendable {
        public let isBar: Bool
        public let isWide: Bool
    }

    /// The 9 elements of each character, bar first: `n` narrow, `w` wide.
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

    /// Elements of `value` wrapped in the start and stop `*`, with a narrow space
    /// between characters. `nil` if a character doesn't exist in Code 39.
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

    /// Total width in narrow modules, for a given wide/narrow ratio.
    public static func width(of elements: [Element], wideRatio: Double) -> Double {
        elements.reduce(0) { $0 + ($1.isWide ? wideRatio : 1) }
    }
}
