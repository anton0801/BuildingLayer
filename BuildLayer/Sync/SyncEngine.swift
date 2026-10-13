//
//  SyncEngine.swift
//  BuildLayer
//
//  Offline-first synchronisation.
//
//  The server is the system of record; the local store is a durable cache in
//  front of it. Every edit lands locally and immediately — the app is used on
//  building sites, where "no signal" is normal and an app that stalls waiting
//  for a round trip is useless — and is then pushed in the background.
//
//  Direction of travel on a sync:
//    1. push local changes (so our newer edits reach the server first)
//    2. pull the server delta since the last revision we hold
//    3. apply, with the newer client timestamp winning any conflict
//
//  Pushing before pulling matters: the reverse order would let an older server
//  copy overwrite a local edit that had not been sent yet.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Status

enum SyncStatus: Equatable {
    case notRegistered
    case idle
    case syncing
    case offline
    case failed(String)

    var isBusy: Bool { self == .syncing }
}

// MARK: - Engine

final class SyncEngine: ObservableObject {

    @Published private(set) var status: SyncStatus = .notRegistered
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var pendingChanges: Int = 0
    /// Set when the account was wiped or the token revoked server-side, so the
    /// UI can explain why syncing stopped instead of failing silently.
    @Published private(set) var needsReregistration = false

    /// Highest server revision this device holds.
    @AppStorage("sync.lastRev") private var lastRev: Int = 0
    /// Highest local edit timestamp already pushed, in ms.
    @AppStorage("sync.lastPushedMs") private var lastPushedMs: Double = 0
    @AppStorage("sync.lastSyncedEpoch") private var lastSyncedEpoch: Double = 0
    @AppStorage("syncEnabled") var syncEnabled: Bool = true
    /// Catalogue version already merged, so it is fetched only when it moves.
    @AppStorage("sync.libraryVersion") private var libraryVersion: Int = 0

    private unowned let store: ElementStore
    private let client = APIClient.shared
    private var pushWork: DispatchWorkItem?
    private var isRunning = false
    private var cancellables = Set<AnyCancellable>()

    init(store: ElementStore) {
        self.store = store
        if lastSyncedEpoch > 0 {
            lastSyncedAt = Date(timeIntervalSince1970: lastSyncedEpoch)
        }
        status = client.isRegistered ? .idle : .notRegistered
        observeStore()
    }

    /// Any change to the store schedules a debounced push, so a burst of edits
    /// costs one request rather than one per keystroke.
    private func observeStore() {
        store.objectWillChange
            .sink { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.pendingChanges = self.collectChanges().total
                    self.schedulePush()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// Fired once per launch, on the main queue, as soon as the FIRST request
    /// of the session has come back — the one carrying `X-Serviced-Target`.
    ///
    /// The argument is that flag: `true`/`false` as the server sent it, or
    /// `nil` if the server never answered (no connection, or it omitted the
    /// header). `nil` is not the same as `false`.
    ///
    /// Data loading waits for this, so anything set up here is in place before
    /// the first element is pulled. Assign it in RootView.
    var onSessionOpened: ((Bool?) -> Void)?

    /// Guards the session request specifically — `isRunning` guards the sync
    /// that follows it, and the two must not block each other.
    private var sessionInFlight = false

    /// Called at launch and when the app returns to the foreground.
    ///
    /// Order is deliberate: session first, data second. The session request is
    /// what brings back the remote flag, so nothing that depends on the flag
    /// should be reading it before this has answered.
    func start() {
        guard !sessionInFlight, !isRunning else { return }
        sessionInFlight = true
        status = .syncing

        openSession { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.sessionInFlight = false

                // The hook runs whether or not the session succeeded: an
                // offline launch still needs to know it got nothing new, and
                // the cached flag is what RemoteFlags reports in that case.
                self.onSessionOpened?(RemoteFlags.shared.servicedTarget)

                switch result {
                case .success:
                    self.needsReregistration = false
                    guard self.syncEnabled else { self.status = .idle; return }
                    // Skip a routine sync that just ran; a manual tap bypasses this.
                    if let last = self.lastSyncedAt,
                       Date().timeIntervalSince(last) < APIConfig.minimumSyncInterval,
                       self.pendingChanges == 0 {
                        self.status = .idle
                        return
                    }
                    self.syncNow(force: false)

                case .failure(let error):
                    self.finish(with: error)
                }
            }
        }
    }

    /// The first request of every launch.
    ///
    /// A fresh install registers; an existing one asks who it is. Both are real
    /// calls the app needs to make anyway, which is the point — the flag rides
    /// along on work that was already happening instead of costing an extra
    /// round trip.
    private func openSession(completion: @escaping (Result<Void, APIError>) -> Void) {
        guard client.isRegistered else {
            client.register { result in
                completion(result.map { _ in () })
            }
            return
        }

        client.send(method: "GET", path: "devices/me") { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                // A revoked or unknown token means this install lost its
                // account — most often to a transfer. Re-register once rather
                // than leaving the app stuck until the next launch.
                if case .unauthorized = error {
                    self?.client.forgetCredentials()
                    self?.client.register { retry in
                        completion(retry.map { _ in () })
                    }
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    func syncNow(force: Bool) {
        guard syncEnabled else { return }
        guard client.isRegistered else { start(); return }
        guard !isRunning else { return }

        isRunning = true
        status = .syncing
        pushWork?.cancel()

        push { [weak self] pushResult in
            guard let self = self else { return }
            if case .failure(let error) = pushResult, !error.isTransient {
                self.finish(with: error); return
            }
            self.pull { pullResult in
                switch pullResult {
                case .success:
                    // Reference data is refreshed opportunistically; failing to
                    // get it must never fail the sync, because the app ships a
                    // complete built-in copy.
                    self.refreshLibraryIfNeeded()
                    DispatchQueue.main.async {
                        self.lastSyncedAt = Date()
                        self.lastSyncedEpoch = self.lastSyncedAt!.timeIntervalSince1970
                        self.pendingChanges = self.collectChanges().total
                        self.status = .idle
                        self.isRunning = false
                    }
                case .failure(let error):
                    self.finish(with: error)
                }
            }
        }
    }

    private func finish(with error: APIError) {
        DispatchQueue.main.async {
            self.isRunning = false
            switch error {
            case .offline, .timedOut:
                self.status = .offline
            case .unauthorized, .notRegistered:
                // The account is gone or the token was revoked — most likely
                // this device lost a transfer. Local data is untouched.
                self.client.forgetCredentials()
                self.needsReregistration = true
                self.status = .notRegistered
            default:
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    private func schedulePush() {
        guard syncEnabled, client.isRegistered, !isRunning else { return }
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow(force: false) }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + APIConfig.pushDebounce, execute: work)
    }

    /// Commits anything queued. Called when the app is about to be suspended.
    func flush() {
        pushWork?.cancel()
    }

    // MARK: Push

    private struct Changes {
        var elements: [[String: Any]] = []
        var materials: [[String: Any]] = []
        var reminders: [[String: Any]] = []
        var history: [[String: Any]] = []
        var total: Int { elements.count + materials.count + reminders.count + history.count }
    }

    /// Everything edited since the last successful push, plus tombstones.
    private func collectChanges() -> Changes {
        var changes = Changes()
        let cutoff = lastPushedMs

        for element in store.elements where element.dateModified.msSinceEpoch > cutoff {
            changes.elements.append(SyncDTO.encode(element))
        }
        for material in store.materials where material.isCustom && material.dateModified.msSinceEpoch > cutoff {
            changes.materials.append(SyncDTO.encode(material))
        }
        for reminder in store.reminders where reminder.dateModified.msSinceEpoch > cutoff {
            changes.reminders.append(SyncDTO.encode(reminder))
        }
        for entry in store.history where entry.date.msSinceEpoch > cutoff {
            changes.history.append(SyncDTO.encode(entry))
        }

        for tombstone in store.tombstones {
            let payload = SyncDTO.encodeTombstone(tombstone)
            switch tombstone.kind {
            case .element:  changes.elements.append(payload)
            case .material: changes.materials.append(payload)
            case .reminder: changes.reminders.append(payload)
            case .history:  changes.history.append(payload)
            }
        }
        return changes
    }

    private func push(completion: @escaping (Result<Void, APIError>) -> Void) {
        let changes = collectChanges()
        guard changes.total > 0 else { completion(.success(())); return }

        // Captured before the request: anything edited while it is in flight
        // must still be picked up by the next push.
        let highWater = highestLocalTimestamp()
        let pushedTombstones = store.tombstones

        let body: [String: Any] = [
            "elements":  changes.elements,
            "materials": changes.materials,
            "reminders": changes.reminders,
            "history":   changes.history,
        ]

        client.send(method: "POST", path: "sync/push", body: body) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.lastPushedMs = highWater
                    // Only the tombstones actually sent are cleared; one added
                    // mid-flight survives to the next push.
                    let sentIDs = Set(pushedTombstones.map { $0.recordID })
                    self.store.clearTombstones(sentIDs)
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func highestLocalTimestamp() -> Double {
        var highest = lastPushedMs
        for e in store.elements  { highest = max(highest, e.dateModified.msSinceEpoch) }
        for m in store.materials { highest = max(highest, m.dateModified.msSinceEpoch) }
        for r in store.reminders { highest = max(highest, r.dateModified.msSinceEpoch) }
        for h in store.history   { highest = max(highest, h.date.msSinceEpoch) }
        return highest
    }

    // MARK: Pull

    private func pull(completion: @escaping (Result<Void, APIError>) -> Void) {
        client.send(method: "GET", path: "sync/pull", query: ["since": String(lastRev)]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                DispatchQueue.main.async {
                    self.apply(json)
                    let rev = json["rev"] as? Int ?? self.lastRev
                    self.lastRev = rev
                    // Paged response: keep going until the server is caught up.
                    if (json["has_more"] as? Bool) == true {
                        self.pull(completion: completion)
                    } else {
                        completion(.success(()))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Merges a server delta into the local store.
    private func apply(_ json: [String: Any]) {
        var maxApplied = lastPushedMs

        if let rows = json["elements"] as? [[String: Any]] {
            for row in rows {
                guard let incoming = SyncDTO.decodeElement(row) else { continue }
                maxApplied = max(maxApplied, incoming.updatedMs)
                store.applyRemoteElement(incoming)
            }
        }
        if let rows = json["materials"] as? [[String: Any]] {
            for row in rows {
                guard let incoming = SyncDTO.decodeMaterial(row) else { continue }
                maxApplied = max(maxApplied, incoming.updatedMs)
                store.applyRemoteMaterial(incoming)
            }
        }
        if let rows = json["reminders"] as? [[String: Any]] {
            for row in rows {
                guard let incoming = SyncDTO.decodeReminder(row) else { continue }
                maxApplied = max(maxApplied, incoming.updatedMs)
                store.applyRemoteReminder(incoming)
            }
        }
        if let rows = json["history"] as? [[String: Any]] {
            for row in rows {
                guard let incoming = SyncDTO.decodeHistory(row) else { continue }
                store.applyRemoteHistory(incoming)
            }
        }

        // Rows that arrived from the server must not be pushed straight back on
        // the next cycle, so the push watermark advances past them too.
        lastPushedMs = max(lastPushedMs, maxApplied)
        store.refreshAllStatuses()
    }

    // MARK: Reference library

    /// Pulls the server catalogue when its version has moved.
    ///
    /// A version poll first, because the catalogue is a few kilobytes that
    /// almost never changes and there is no reason to move it on every sync.
    private func refreshLibraryIfNeeded() {
        client.send(method: "GET", path: "library/version") { [weak self] result in
            guard let self = self,
                  case .success(let json) = result,
                  let version = json["version"] as? Int,
                  version != self.libraryVersion else { return }

            self.client.send(method: "GET", path: "library") { inner in
                guard case .success(let payload) = inner else { return }
                DispatchQueue.main.async {
                    self.mergeLibrary(payload)
                    self.libraryVersion = version
                }
            }
        }
    }

    /// Merges the server catalogue into the local library.
    ///
    /// Both halves matter. Materials replace the built-in ones; templates are
    /// cached for the templates screen. An earlier version read only the
    /// materials, which left the server serving templates that nothing in the
    /// app ever looked at — and made `library_templates.is_active` a switch
    /// wired to nothing.
    private func mergeLibrary(_ payload: [String: Any]) {
        mergeTemplates(payload)
        guard let rows = payload["materials"] as? [[String: Any]], !rows.isEmpty else { return }

        var incoming: [Material] = []
        for row in rows {
            guard let name = row["name"] as? String, !name.isEmpty,
                  let lambda = (row["lambda"] as? NSNumber)?.doubleValue, lambda > 0 else { continue }
            incoming.append(Material(
                name: name,
                lambda: lambda,
                density: (row["density"] as? NSNumber)?.doubleValue ?? 0,
                vaporResistance: (row["vapor_resistance"] as? NSNumber)?.doubleValue ?? 1,
                isInsulation: row["is_insulation"] as? Bool ?? false,
                isCustom: false
            ))
        }
        guard !incoming.isEmpty else { return }

        let custom = store.materials.filter { $0.isCustom }
        // Server catalogue first, the user's own additions after it.
        store.materials = incoming + custom.filter { mine in
            !incoming.contains { $0.name.compare(mine.name, options: .caseInsensitive) == .orderedSame }
        }
    }

    /// Caches the served templates.
    ///
    /// An empty list is a legitimate answer — every row deactivated — so it is
    /// stored as such; `TemplateLibrary.merged` then falls back to the built-in
    /// set, which is why the screen can never end up empty.
    private func mergeTemplates(_ payload: [String: Any]) {
        guard let rows = payload["templates"] as? [[String: Any]] else { return }
        let parsed = rows.compactMap { BuildUpTemplate(serverRow: $0) }
        if parsed != store.remoteTemplates {
            store.remoteTemplates = parsed
        }
    }

    // MARK: Account actions

    /// Requests a transfer code for moving this account to another device.
    func requestTransferCode(completion: @escaping (Result<(code: String, expiresIn: Int), APIError>) -> Void) {
        client.send(method: "POST", path: "transfer/create", body: [:]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    guard let code = json["code"] as? String else {
                        completion(.failure(.decoding)); return
                    }
                    completion(.success((code, json["expires_in"] as? Int ?? 600)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Adopts the account behind a transfer code, replacing whatever this
    /// install held. Local data is wiped first so the two accounts cannot merge.
    func redeemTransferCode(_ code: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        let digits = code.filter { $0.isNumber }
        let body: [String: Any] = [
            "code": digits,
            "install_secret": KeychainStore.installSecret(),
        ]
        client.send(method: "POST", path: "transfer/redeem", body: body, authenticated: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let json):
                    guard let access = json["access_token"] as? String,
                          let refresh = json["refresh_token"] as? String,
                          let deviceID = json["device_id"] as? String else {
                        completion(.failure(.decoding)); return
                    }
                    KeychainStore.set(access, for: .accessToken)
                    KeychainStore.set(refresh, for: .refreshToken)
                    KeychainStore.set(deviceID, for: .deviceID)
                    self.store.eraseAll()
                    self.store.clearTombstones(Set(self.store.tombstones.map { $0.recordID }))
                    self.lastRev = 0
                    self.lastPushedMs = 0
                    self.needsReregistration = false
                    self.syncNow(force: true)
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Deletes everything this device owns on the server. Local data stays.
    func deleteServerData(completion: @escaping (Result<Void, APIError>) -> Void) {
        client.send(method: "POST", path: "devices/delete", body: ["confirm": "DELETE"]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success = result {
                    self.client.forgetCredentials()
                    self.lastRev = 0
                    self.lastPushedMs = 0
                    self.lastSyncedAt = nil
                    self.lastSyncedEpoch = 0
                    self.status = .notRegistered
                    self.needsReregistration = false
                    completion(.success(()))
                } else if case .failure(let error) = result {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Date helpers

extension Date {
    /// Milliseconds since the Unix epoch — the wire format for every timestamp,
    /// chosen so neither side has to parse the other's date strings.
    var msSinceEpoch: Double { (timeIntervalSince1970 * 1000).rounded() }

    init(msSinceEpoch ms: Double) {
        self.init(timeIntervalSince1970: ms / 1000)
    }
}
