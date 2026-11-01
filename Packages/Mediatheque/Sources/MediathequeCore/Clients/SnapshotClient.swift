// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation

/// Reads and writes the snapshot in the App Group container (shared with the widget).
@DependencyClient
public struct SnapshotClient: Sendable {
    public var load: @Sendable () -> AccountSnapshot? = { nil }
    public var save: @Sendable (_ snapshot: AccountSnapshot) -> Void
    public var clear: @Sendable () -> Void
}

extension SnapshotClient: DependencyKey {
    /// Read from the app's or the widget's Info.plist (`AppGroupIdentifier`, set by Config/*.xcconfig).
    /// Tests and previews have no such key: the fallback names a container that simply doesn't exist.
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        ?? "group.com.example.mediatheques-villejuif"

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
            // Protected until the device has been unlocked once.
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
