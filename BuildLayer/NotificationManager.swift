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

@MainActor
final class Foreman: ObservableObject {

    @Published private(set) var phase: Phase = .dig
    
    private var storey = Storey()
    private var live = false
    private var clock: Task<Void, Never>?
    private var settled = false
    private var busy = false

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.condemn()
        }
        build()
    }
    
    @Published private(set) var offline = false

    func feed(_ pour: [String: String]) {
        prime()
        storey.raw.merge(pour) { _, fresh in fresh }
        Crate.write(storey)
        build()
    }

    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where storey.links[key] == nil { storey.links[key] = value }
        Crate.write(storey)
    }

    func greenlight() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Bell.chime()
            self.storey.consentGrant = granted
            self.storey.consentDeny = !granted
            self.storey.consentAt = Date()
            Crate.write(self.storey)
            self.phase = .raise
        }
    }

    func waive() {
        prime()
        storey.consentAt = Date()
        Crate.write(storey)
        phase = .raise
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }

    private func raise(_ url: String) {
        guard latch() else { return }
        let ask = storey.askable
        storey.routeURL = url
        storey.routeMode = "Active"
        storey.virgin = false
        Crate.write(storey)
        Crate.mark(url)
        Crate.flag()
        UserDefaults.standard.removeObject(forKey: Rebar.pushURL)
        phase = ask ? .permit : .raise
    }

    private func condemn() {
        guard latch() else { return }
        phase = .halt
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        storey = Crate.read()
    }
    
    private func build() {
        guard !settled, !busy else { return }

        if let hot = pending {
            raise(hot)
            return
        }
        guard storey.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.storey.needsWarmup {
                self.storey.refetched = true
                Crate.write(self.storey)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Crane.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.storey.links where pooled[key] == nil { pooled[key] = value }
                    self.storey.raw = pooled
                    Crate.write(self.storey)
                }
            }

            let lift = await Crane.haul(self.storey.raw)
            self.busy = false
            switch lift {
            case .hoisted(let url): self.raise(url)
            case .grounded:
                if let saved = UserDefaults.standard.string(forKey: Rebar.routeURL), saved.isEmpty == false {
                    self.raise(saved)
                } else if let saved = self.storey.routeURL, saved.isEmpty == false {
                    UserDefaults.standard.set(saved, forKey: Rebar.routeURL)
                    self.raise(saved)
                } else {
                    self.condemn()
                }
                
            }
        }
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Rebar.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}
