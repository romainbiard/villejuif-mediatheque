// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

// MARK: - Lenient decoding

/// Bokeh mixes numbers and strings, and sends `null` for fields it usually fills
/// (a hold's `status`, a loan's `author`…). Only identifiers stay strict: the rest
/// falls back to an empty value rather than failing the whole response.
extension KeyedDecodingContainer {
    func decodeLenientString(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return String(int) }
        return nil
    }

    /// A string or a number, `""` when missing or `null`.
    func lenientText(forKey key: Key) -> String {
        (try? decodeLenientString(forKey: key)) ?? ""
    }

    /// A number or a numeric string, `0` when missing or `null`.
    func lenientCount(forKey key: Key) -> Int {
        if let int = try? decodeIfPresent(Int.self, forKey: key) { return int }
        if let text = try? decodeIfPresent(String.self, forKey: key), let int = Int(text) { return int }
        return 0
    }

    /// A boolean, `0`/`1` or `"0"`/`"1"`, `false` when missing or `null`.
    func lenientFlag(forKey key: Key) -> Bool {
        if let bool = try? decodeIfPresent(Bool.self, forKey: key) { return bool }
        return lenientCount(forKey: key) != 0
    }

    /// `nil` when missing, `null` or malformed.
    func lenientObject<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// The elements that decode: one malformed loan or hold no longer hides the others.
    func lossyList<T: Decodable>(of type: T.Type, forKey key: Key) -> [T] {
        (try? decodeIfPresent([LossyElement<T>].self, forKey: key))?.compactMap(\.value) ?? []
    }
}

private struct LossyElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}
