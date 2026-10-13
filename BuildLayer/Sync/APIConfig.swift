//
//  APIConfig.swift
//  BuildLayer
//
//  The endpoint is compiled in and cannot be changed at runtime.
//
//  There is deliberately no setting, no debug field and no launch argument that
//  points the app at a different host. A user-editable server address is both an
//  App Review problem and a real one: anything that can retarget the client can
//  be used to redirect a token to a server the user does not control.
//

import Foundation

enum APIConfig {

    /// The one and only host this build talks to.
    static let baseURL = URL(string: "https://buildinglayer.site/api/v1")!

    /// Seconds before a request is abandoned. Short enough that a dead server
    /// does not leave the sync indicator spinning; the work is retried anyway.
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 60

    /// Shared key used to sign every request, proving the caller is this build.
    ///
    /// Stored split and XOR-masked rather than as a plain literal, because a
    /// literal shows up in `strings BuildLayer` in one command. This is
    /// obfuscation, not secrecy: anyone who can run a debugger will recover it.
    /// It raises the cost of casual scripted abuse — the bearer token is what
    /// actually protects a device's data, and the server treats the signature
    /// as client attestation only.
    ///
    /// MUST match `app_secret` in the server's config.php.
    static var signingKey: String {
        let mask: [UInt8] = [0x5A, 0x3C, 0x7E, 0x11, 0x28, 0x64, 0x9D, 0xC3]
        var out = [UInt8]()
        out.reserveCapacity(maskedSecret.count)
        for (index, byte) in maskedSecret.enumerated() {
            out.append(byte ^ mask[index % mask.count])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Replace together with the server's app_secret. Regenerate with:
    ///   php -r "echo bin2hex(random_bytes(32));"
    /// then run Tools/mask-secret.swift to produce this array.
    private static let maskedSecret: [UInt8] = [
        0x62, 0x5E, 0x48, 0x72, 0x1D, 0x52, 0xFC, 0xA1, 0x6B, 0x0B, 0x1B, 0x74,
        0x4D, 0x5D, 0xAF, 0xF0, 0x6E, 0x0A, 0x4C, 0x27, 0x1D, 0x57, 0xA9, 0xFA,
        0x69, 0x0D, 0x47, 0x29, 0x1C, 0x01, 0xA9, 0xF2, 0x6D, 0x0A, 0x1D, 0x24,
        0x4D, 0x51, 0xFB, 0xF0, 0x39, 0x5D, 0x1B, 0x23, 0x1A, 0x55, 0xAC, 0xF4,
        0x68, 0x05, 0x49, 0x23, 0x4B, 0x56, 0xFE, 0xA7, 0x3C, 0x59, 0x4C, 0x28,
        0x10, 0x01, 0xAC, 0xF7,
    ]

    /// How long after the last local edit a push is attempted.
    static let pushDebounce: TimeInterval = 4
    /// Minimum gap between automatic full syncs.
    static let minimumSyncInterval: TimeInterval = 60
}
