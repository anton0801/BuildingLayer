//
//  APIClient.swift
//  BuildLayer
//
//  Signs, sends and decodes. Knows nothing about elements or layers — that is
//  the sync engine's job — so the transport can be reasoned about on its own.
//

import Foundation
import CryptoKit
import UIKit

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case offline
    case timedOut
    case unauthorized
    case rateLimited(retryAfter: Int)
    case server(code: String, message: String, status: Int)
    case decoding
    case notRegistered

    var errorDescription: String? {
        switch self {
        case .offline:               return "No connection."
        case .timedOut:              return "The server did not respond."
        case .unauthorized:          return "This device needs to sign in again."
        case .rateLimited(let s):    return "Too many requests. Try again in \(s)s."
        case .server(_, let m, _):   return m
        case .decoding:              return "The server sent something unexpected."
        case .notRegistered:         return "This device is not registered yet."
        }
    }

    /// Whether retrying the same request later could plausibly succeed.
    var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited:
            return true
        case .server(_, _, let status):
            return status >= 500
        default:
            return false
        }
    }
}

// MARK: - Client

final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    /// Serialises token refresh so a burst of 401s triggers one refresh, not five.
    private let refreshQueue = DispatchQueue(label: "buildlayer.api.refresh")
    private var isRefreshing = false

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = APIConfig.requestTimeout
        config.timeoutIntervalForResource = APIConfig.resourceTimeout
        // Nothing from this API should ever be served from a cache: a stale
        // sync response would silently resurrect deleted rows.
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    var isRegistered: Bool { KeychainStore.get(.accessToken) != nil }
    var deviceID: String? { KeychainStore.get(.deviceID) }

    // MARK: Request building

    /// Builds a signed request. See Signature.php for the matching canonical form.
    private func makeRequest(method: String,
                             path: String,
                             query: [String: String] = [:],
                             body: [String: Any]? = nil,
                             authenticated: Bool) throws -> URLRequest {

        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.decoding }

        var request = URLRequest(url: url)
        request.httpMethod = method

        var rawBody = Data()
        if let body = body {
            rawBody = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = rawBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = Self.randomHex(16)

        // The signed path is the URL path only — never the query string — so it
        // must match exactly what the server reconstructs.
        let signedPath = "/v1/" + path
        let bodyHash = SHA256.hash(data: rawBody).map { String(format: "%02x", $0) }.joined()
        let canonical = [method, signedPath, timestamp, nonce, bodyHash].joined(separator: "\n")

        let key = SymmetricKey(data: Data(APIConfig.signingKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
        request.setValue(Data(mac).base64EncodedString(), forHTTPHeaderField: "X-BL-Signature")
        request.setValue(timestamp, forHTTPHeaderField: "X-BL-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-BL-Nonce")

        if authenticated {
            guard let token = KeychainStore.get(.accessToken) else { throw APIError.notRegistered }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Sending

    /// Sends a request, refreshing the access token once if it has expired.
    func send(method: String,
              path: String,
              query: [String: String] = [:],
              body: [String: Any]? = nil,
              authenticated: Bool = true,
              allowRetryAfterRefresh: Bool = true,
              completion: @escaping (Result<[String: Any], APIError>) -> Void) {

        let request: URLRequest
        do {
            request = try makeRequest(method: method, path: path, query: query,
                                      body: body, authenticated: authenticated)
        } catch let error as APIError {
            completion(.failure(error)); return
        } catch {
            completion(.failure(.decoding)); return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error as NSError? {
                switch error.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
                     NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                    completion(.failure(.offline))
                case NSURLErrorTimedOut:
                    completion(.failure(.timedOut))
                default:
                    completion(.failure(.offline))
                }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.decoding))
                return
            }

            // Captured before the status is even looked at: the server sends
            // the flag on error responses too, and a 401 on a cold launch is a
            // perfectly ordinary first call.
            RemoteFlags.shared.capture(from: http)

            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure(.decoding))
                return
            }

            if http.statusCode == 200 || http.statusCode == 201 {
                completion(.success(json))
                return
            }

            let errorBody = json["error"] as? [String: Any] ?? [:]
            let code = errorBody["code"] as? String ?? "unknown"
            let message = errorBody["message"] as? String ?? "Request failed."

            // An expired access token is normal and recoverable: refresh once
            // and replay. A revoked one is not, and must not loop.
            if http.statusCode == 401, code == "token_expired", allowRetryAfterRefresh {
                self.refreshAccessToken { refreshed in
                    if refreshed {
                        self.send(method: method, path: path, query: query, body: body,
                                  authenticated: authenticated,
                                  allowRetryAfterRefresh: false, completion: completion)
                    } else {
                        completion(.failure(.unauthorized))
                    }
                }
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(.unauthorized)); return
            }
            if http.statusCode == 429 {
                let meta = errorBody["meta"] as? [String: Any] ?? [:]
                completion(.failure(.rateLimited(retryAfter: meta["retry_after"] as? Int ?? 60)))
                return
            }
            completion(.failure(.server(code: code, message: message, status: http.statusCode)))
        }.resume()
    }

    // MARK: Identity

    /// Registers this install, or re-attaches to its existing account.
    func register(completion: @escaping (Result<Void, APIError>) -> Void) {
        let body: [String: Any] = [
            "install_secret": KeychainStore.installSecret(),
            "platform": "ios",
            "app_version": Bundle.main.appVersionText,
            "os_version": UIDevice.current.systemVersion,
            "model": UIDevice.current.model,
        ]
        send(method: "POST", path: "devices/register", body: body, authenticated: false) { result in
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
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        refreshQueue.async {
            if self.isRefreshing {
                // Another request is already refreshing; treat this one as
                // failed rather than piling on a second refresh.
                completion(false); return
            }
            self.isRefreshing = true
            guard let refresh = KeychainStore.get(.refreshToken) else {
                self.isRefreshing = false
                completion(false); return
            }
            self.send(method: "POST", path: "devices/refresh",
                      body: ["refresh_token": refresh],
                      authenticated: false, allowRetryAfterRefresh: false) { result in
                self.refreshQueue.async { self.isRefreshing = false }
                if case .success(let json) = result, let access = json["access_token"] as? String {
                    KeychainStore.set(access, for: .accessToken)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    /// Drops local credentials. Used when the server says this device is gone.
    func forgetCredentials() {
        KeychainStore.remove(.accessToken)
        KeychainStore.remove(.refreshToken)
        KeychainStore.remove(.deviceID)
    }

    // MARK: Helpers

    static func randomHex(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
