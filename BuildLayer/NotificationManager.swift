//
//  NotificationManager.swift
//  BuildLayer
//
//  Real local notifications via UNUserNotificationCenter — used for the build
//  reminders (vapor barrier, acclimatize insulation, verify code, re-inspect).
//

import Foundation
import UserNotifications
import SwiftUI

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorized: Bool = false

    private init() { refreshAuthorization() }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self.authorized = granted
                    completion?(granted)
                }
            }
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }
    }

    /// Schedule (or reschedule) a reminder. Returns via completion whether it was set.
    func schedule(_ reminder: Reminder, completion: ((Bool) -> Void)? = nil) {
        func doSchedule() {
            let content = UNMutableNotificationContent()
            content.title = reminder.kind.rawValue
            content.body = reminder.elementName.isEmpty
                ? reminder.kind.detail
                : "\(reminder.kind.detail) (\(reminder.elementName))"
            content.sound = .default

            // A calendar trigger whose components are already in the past never
            // fires; the caller was told the reminder had been scheduled anyway.
            guard reminder.date > Date() else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id.uuidString,
                                                content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async { completion?(error == nil) }
            }
        }

        if authorized {
            doSchedule()
        } else {
            requestAuthorization { granted in
                if granted { doSchedule() } else { completion?(false) }
            }
        }
    }

    func cancel(_ reminder: Reminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Drops reminders whose time has passed and which no longer have a pending
    /// notification. The list used to accumulate stale entries for ever, with
    /// nothing on screen distinguishing them from the ones still scheduled.
    func pruneDeliveredReminders(_ store: ElementStore) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let pending = Set(requests.map { $0.identifier })
            DispatchQueue.main.async {
                let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
                store.reminders.removeAll { !pending.contains($0.id.uuidString) && $0.date < cutoff }
            }
        }
    }

    /// Fire a confirmation that the report/reminder action succeeded (5s out).
    func confirm(_ title: String, _ body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
