// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import BokehAPI
import Foundation
import MediathequeCore
import Testing

struct LoadErrorTests {
    /// The site answered: saying it "doesn't respond" sent us looking for a network problem.
    @Test func anUnreadableAnswerIsNotAnUnreachableSite() {
        let decoding = DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "null"))
        #expect(LoadError(decoding) == .unreadableAnswer)
        #expect(LoadError(BokehError.unexpectedFormat("csrftoken introuvable")) == .unreadableAnswer)
        #expect(LoadError(URLError(.timedOut)) == .siteUnavailable)
        #expect(LoadError.unreadableAnswer.title != LoadError.siteUnavailable.title)
    }
}
