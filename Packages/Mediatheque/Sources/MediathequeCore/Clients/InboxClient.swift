import Dependencies
import DependenciesMacros
import Foundation

/// Historique du centre de notifications, dans l'App Group (l'app et la tâche de fond l'alimentent).
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
