import Dependencies
import DependenciesMacros
import Foundation

/// Lecture et écriture du snapshot dans le conteneur de l'App Group (partagé avec le widget).
@DependencyClient
public struct SnapshotClient: Sendable {
    public var load: @Sendable () -> AccountSnapshot? = { nil }
    public var save: @Sendable (_ snapshot: AccountSnapshot) -> Void
    public var clear: @Sendable () -> Void
}

extension SnapshotClient: DependencyKey {
    public static let appGroup = "group.com.rbiard.mediatheques-villejuif"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "account-snapshot.json")
    }

    public static let liveValue = SnapshotClient(
        load: {
            guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AccountSnapshot.self, from: data)
        },
        save: { snapshot in
            guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
            // Protégé tant que l'appareil n'a pas été déverrouillé une première fois.
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        },
        clear: {
            guard let url = fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    )

    public static let previewValue = SnapshotClient(
        load: { AccountSnapshot(loans: SampleData.loans, holds: SampleData.holds, updatedAt: .now) },
        save: { _ in },
        clear: {}
    )

    public static let testValue = SnapshotClient()
}

extension DependencyValues {
    public var snapshotClient: SnapshotClient {
        get { self[SnapshotClient.self] }
        set { self[SnapshotClient.self] = newValue }
    }
}
