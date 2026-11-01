// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation

/// Notification center history, in the App Group (fed by the app and the background task).
@DependencyClient
public struct InboxClient: Sendable {
    public var load: @Sendable () -> Inbox = { Inbox() }
    public var save: @Sendable (_ inbox: Inbox) -> Void
    public var clear: @Sendable () -> Void
}

extension InboxClient: DependencyKey {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SnapshotClient.appGroup)?
            .appending(path: "inbox.json")
    }

    public static let liveValue = InboxClient(
        load: {
            guard let url = fileURL, let data = try? Data(contentsOf: url) else { return Inbox() }
            return (try? JSONDecoder().decode(Inbox.self, from: data)) ?? Inbox()
        },
        save: { inbox in
            guard let url = fileURL, let data = try? JSONEncoder().encode(inbox) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        },
        clear: {
            guard let url = fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    )

    public static let previewValue = InboxClient(
        load: { SampleData.inbox },
        save: { _ in },
        clear: {}
    )

    public static let testValue = InboxClient()
}

extension DependencyValues {
    public var inboxClient: InboxClient {
        get { self[InboxClient.self] }
        set { self[InboxClient.self] = newValue }
    }
}
