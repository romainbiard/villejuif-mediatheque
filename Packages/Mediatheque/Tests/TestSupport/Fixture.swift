// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation
import Testing

/// Pages and responses captured from the real portal, anonymized (Fixtures/).
public enum Fixture {
    public static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    public static func string(_ name: String) throws -> String {
        try String(decoding: data(name), as: UTF8.self)
    }
}
