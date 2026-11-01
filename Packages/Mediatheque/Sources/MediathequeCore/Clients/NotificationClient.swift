// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Dependencies
import DependenciesMacros
import Foundation
import OSLog
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Notification authorization status, as reported by iOS.
public enum NotificationAuthorization: Sendable, Equatable {
    /// iOS hasn't asked yet: the system prompt is still available (only once).
    case notDetermined
    case denied
    case authorized
}

/// Local notifications: due-date reminders, holds ready, weekly agenda.
@DependencyClient
public struct NotificationClient: Sendable {
    public var authorizationStatus: @Sendable () async -> NotificationAuthorization = { .notDetermined }
    public var requestAuthorization: @Sendable () async -> Bool = { false }
    /// Weekly agenda reminder, Mondays at 9 am; `false` removes it.
    public var setAgendaDigest: @Sendable (_ enabled: Bool) async -> Void
    /// Replaces all scheduled due-date reminders with `reminders`.
    public var replaceLoanReminders: @Sendable (_ reminders: [Reminder]) async -> Void
    public var deliver: @Sendable (_ reminder: Reminder) async -> Void
    public var removeAll: @Sendable () async -> Void
}

extension NotificationClient: DependencyKey {
    static let loanPrefix = "loan-"
    static let agendaDigestID = "agenda-weekly"
    static let logger = Logger(subsystem: "com.rbiard.mediatheques-villejuif", category: "notifications")

    public static let liveValue = NotificationClient(
        authorizationStatus: {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied: .denied
            default: .authorized
            }
        },
        requestAuthorization: {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                // Without this log, a refusal by iOS (rather than the user) would go unnoticed.
                logger.error("Autorisation des notifications impossible : \(error.localizedDescription, privacy: .public)")
                return false
            }
        },
        setAgendaDigest: { enabled in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [agendaDigestID])
            guard enabled else { return }
            let content = UNMutableNotificationContent()
            content.title = .local("Cette semaine dans vos médiathèques")
            content.body = .local("Lectures, ateliers, projections : découvrez les animations à venir dans l'agenda.")
            content.threadIdentifier = "agenda"
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0, weekday: 2), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: agendaDigestID, content: content, trigger: trigger))
        },
        replaceLoanReminders: { reminders in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(loanPrefix) })
            let calendar = Calendar.paris
            for reminder in reminders {
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content(for: reminder), trigger: trigger))
            }
        },
        deliver: { reminder in
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: reminder.id, content: content(for: reminder), trigger: nil)
            )
        },
        removeAll: {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    )

    private static func content(for reminder: Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.id.hasPrefix(loanPrefix) ? "loans" : "holds"
        return content
    }

    public static let previewValue = NotificationClient(
        authorizationStatus: { .notDetermined },
        requestAuthorization: { true },
        setAgendaDigest: { _ in },
        replaceLoanReminders: { _ in },
        deliver: { _ in },
        removeAll: {}
    )

    public static let testValue = NotificationClient()
}

extension DependencyValues {
    public var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}

/// Reminder settings, chosen after sign-in and then in Settings.
public struct ReminderSettings: Hashable, Sendable {
    public var loanReminders: Bool
    public var daysBefore: Int
    public var holdAlerts: Bool
    /// Off by default: only returns and holds are useful to everyone.
    public var agendaDigest: Bool

    public init(loanReminders: Bool = true, daysBefore: Int = 3, holdAlerts: Bool = true, agendaDigest: Bool = false) {
        self.loanReminders = loanReminders
        self.daysBefore = daysBefore
        self.holdAlerts = holdAlerts
        self.agendaDigest = agendaDigest
    }

    public enum Key {
        public static let loanReminders = "reminders.loans"
        public static let daysBefore = "reminders.daysBefore"
        public static let holdAlerts = "reminders.holds"
        public static let agendaDigest = "reminders.agendaDigest"
        public static let faceID = "security.faceID"
        public static let onboardingDone = "account.onboardingDone"
    }

    /// Reads from the shared UserDefaults (the App Group, for the background task as well as the app).
    public static func current(_ defaults: UserDefaults = .shared) -> ReminderSettings {
        ReminderSettings(
            loanReminders: defaults.object(forKey: Key.loanReminders) as? Bool ?? true,
            daysBefore: defaults.object(forKey: Key.daysBefore) as? Int ?? 3,
            holdAlerts: defaults.object(forKey: Key.holdAlerts) as? Bool ?? true,
            agendaDigest: defaults.object(forKey: Key.agendaDigest) as? Bool ?? false
        )
    }
}

extension UserDefaults {
    /// App Group UserDefaults, read by the app, the background task and the widget.
    public static var shared: UserDefaults {
        UserDefaults(suiteName: SnapshotClient.appGroup) ?? .standard
    }
}

/// Account sync: new snapshot, rescheduled reminders, notifications for holds that are ready.
/// Called after sign-in, each time the account is opened, and by the background task.
public enum AccountSync {
    @discardableResult
    public static func run(settings: ReminderSettings) async throws -> AccountSnapshot {
        @Dependency(\.accountClient) var account
        @Dependency(\.snapshotClient) var snapshots
        @Dependency(\.notificationClient) var notifications
        @Dependency(\.inboxClient) var inboxClient
        @Dependency(\.date.now) var now

        let snapshot = AccountSnapshot(loans: try await account.loans(), holds: try await account.holds(), updatedAt: now)
        let previous = snapshots.load()
        snapshots.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        let reminders = settings.loanReminders
            ? ReminderPlanner.loanReminders(for: snapshot.loans, daysBefore: settings.daysBefore, now: now, calendar: .paris)
            : []
        await notifications.replaceLoanReminders(reminders)
        await notifications.setAgendaDigest(settings.agendaDigest)

        // Notification center: keep a record of what the reminders announced.
        var inbox = inboxClient.load()
        inbox.merge(
            InboxPlanner.items(for: snapshot, daysBefore: settings.daysBefore, now: now, calendar: .paris),
            now: now,
            calendar: .paris
        )
        inboxClient.save(inbox)

        // On the very first snapshot, don't notify about what the patron already sees on screen.
        if settings.holdAlerts, previous != nil {
            for hold in snapshot.newlyReadyHolds(since: previous) {
                await notifications.deliver(ReminderPlanner.holdReadyReminder(for: hold))
            }
        }
        return snapshot
    }

    /// Library message read from the account, added to the notification center.
    public static func record(libraryMessage: String?) {
        @Dependency(\.inboxClient) var inboxClient
        @Dependency(\.date.now) var now
        guard let libraryMessage, !libraryMessage.isEmpty else { return }
        var inbox = inboxClient.load()
        inbox.merge([InboxPlanner.libraryMessage(libraryMessage, now: now)], now: now, calendar: .paris)
        inboxClient.save(inbox)
    }

    /// On sign-out: no more snapshot, reminders or history on the device.
    public static func reset() async {
        @Dependency(\.snapshotClient) var snapshots
        @Dependency(\.notificationClient) var notifications
        @Dependency(\.inboxClient) var inboxClient
        snapshots.clear()
        inboxClient.clear()
        await notifications.removeAll()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
