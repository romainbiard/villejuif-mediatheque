import Dependencies
import DependenciesMacros
import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Notifications locales : rappels de retour et réservations arrivées.
@DependencyClient
public struct NotificationClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool = { false }
    /// Remplace tous les rappels de retour programmés par `reminders`.
    public var replaceLoanReminders: @Sendable (_ reminders: [Reminder]) async -> Void
    public var deliver: @Sendable (_ reminder: Reminder) async -> Void
    public var removeAll: @Sendable () async -> Void
}

extension NotificationClient: DependencyKey {
    static let loanPrefix = "loan-"

    public static let liveValue = NotificationClient(
        requestAuthorization: {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
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
        requestAuthorization: { true }, replaceLoanReminders: { _ in }, deliver: { _ in }, removeAll: {}
    )

    public static let testValue = NotificationClient()
}

extension DependencyValues {
    public var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}

/// Réglages des rappels, choisis après la connexion puis dans Réglages.
public struct ReminderSettings: Hashable, Sendable {
    public var loanReminders: Bool
    public var daysBefore: Int
    public var holdAlerts: Bool

    public init(loanReminders: Bool = true, daysBefore: Int = 3, holdAlerts: Bool = true) {
        self.loanReminders = loanReminders
        self.daysBefore = daysBefore
        self.holdAlerts = holdAlerts
    }

    public enum Key {
        public static let loanReminders = "reminders.loans"
        public static let daysBefore = "reminders.daysBefore"
        public static let holdAlerts = "reminders.holds"
        public static let faceID = "security.faceID"
        public static let onboardingDone = "account.onboardingDone"
    }

    /// Lecture dans les UserDefaults partagés (l'App Group, pour la tâche de fond comme pour l'app).
    public static func current(_ defaults: UserDefaults = .shared) -> ReminderSettings {
        ReminderSettings(
            loanReminders: defaults.object(forKey: Key.loanReminders) as? Bool ?? true,
            daysBefore: defaults.object(forKey: Key.daysBefore) as? Int ?? 3,
            holdAlerts: defaults.object(forKey: Key.holdAlerts) as? Bool ?? true
        )
    }
}

extension UserDefaults {
    /// UserDefaults de l'App Group, lus par l'app, la tâche de fond et le widget.
    public static var shared: UserDefaults {
        UserDefaults(suiteName: SnapshotClient.appGroup) ?? .standard
    }
}

/// Synchronisation du compte : nouveau snapshot, rappels reprogrammés, réservations arrivées notifiées.
/// Appelée après la connexion, à chaque ouverture du compte et par la tâche de fond.
public enum AccountSync {
    @discardableResult
    public static func run(settings: ReminderSettings) async throws -> AccountSnapshot {
        @Dependency(\.accountClient) var account
        @Dependency(\.snapshotClient) var snapshots
        @Dependency(\.notificationClient) var notifications
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

        // Au tout premier snapshot, on ne notifie pas ce que l'abonné voit déjà à l'écran.
        if settings.holdAlerts, previous != nil {
            for hold in snapshot.newlyReadyHolds(since: previous) {
                await notifications.deliver(ReminderPlanner.holdReadyReminder(for: hold))
            }
        }
        return snapshot
    }

    /// À la déconnexion : plus de snapshot ni de rappels sur l'appareil.
    public static func reset() async {
        @Dependency(\.snapshotClient) var snapshots
        @Dependency(\.notificationClient) var notifications
        snapshots.clear()
        await notifications.removeAll()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
