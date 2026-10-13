//
//  RemoteFlags.swift
//  BuildLayer
//
//  Server-controlled flags delivered in response headers.
//
//  The server sends `X-Serviced-Target: true|false` on every response, so the
//  value arrives on the first call the app makes — which is the session check
//  in SyncEngine.openSession(). This type captures it, caches the last known
//  answer, and publishes it; deciding what to do with it is left to the feature
//  that needs it.
//
//  There is deliberately no fetch method here. A dedicated request just for the
//  flag would be a second round trip for something the session call already
//  carries, and a second code path that could disagree with the first.
//

import Foundation
import SwiftUI

final class RemoteFlags: ObservableObject {

    static let shared = RemoteFlags()

    /// Header the server sends the flag in.
    static let headerName = "x-serviced-target"

    /// nil until the server has answered at least once on this install.
    ///
    /// Three states, not two, and the difference matters: "not asked yet" is
    /// not the same as "the server said false", and code that treats them alike
    /// will behave differently on a cold launch with no connection.
    @Published private(set) var servicedTarget: Bool?

    /// When the value was last received, so a caller can judge how stale it is.
    @Published private(set) var lastUpdated: Date?

    /// Survives relaunch, so an offline start uses the last known answer
    /// instead of nothing.
    @AppStorage("flags.servicedTarget") private var cachedRaw: String = ""
    @AppStorage("flags.servicedTargetAt") private var cachedAt: Double = 0

    private init() {
        if cachedRaw == "true" { servicedTarget = true }
        else if cachedRaw == "false" { servicedTarget = false }
        if cachedAt > 0 { lastUpdated = Date(timeIntervalSince1970: cachedAt) }
    }

    // MARK: Capture

    /// Reads the flag out of any response. Called for every API call, so the
    /// value keeps itself current without a dedicated poll.
    func capture(from response: HTTPURLResponse) {
        let raw: String?
        if #available(iOS 13.0, *) {
            // Case-insensitive: header casing is not guaranteed across proxies,
            // and `allHeaderFields` lookups are case-sensitive.
            raw = response.value(forHTTPHeaderField: Self.headerName)
        } else {
            raw = nil
        }
        guard let value = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else {
            return   // header absent: keep whatever we already had
        }

        let parsed: Bool
        switch value {
        case "true", "1", "yes", "on":   parsed = true
        case "false", "0", "no", "off":  parsed = false
        default:                          return   // unrecognised: ignore, don't guess
        }

        DispatchQueue.main.async {
            let now = Date()
            self.cachedRaw = parsed ? "true" : "false"
            self.cachedAt = now.timeIntervalSince1970
            self.lastUpdated = now
            if self.servicedTarget != parsed {
                self.servicedTarget = parsed
            }
        }
    }

}
