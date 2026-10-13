#!/usr/bin/env swift
//
//  mask-secret.swift
//  Produces the `maskedSecret` byte array for APIConfig.swift.
//
//  Usage:  swift Tools/mask-secret.swift <app_secret>
//
//  The mask is not encryption — it only keeps the key out of `strings`. Keep
//  the mask here identical to the one in APIConfig.swift.
//
import Foundation

let mask: [UInt8] = [0x5A, 0x3C, 0x7E, 0x11, 0x28, 0x64, 0x9D, 0xC3]

guard CommandLine.arguments.count == 2 else {
    print("usage: swift mask-secret.swift <app_secret>")
    exit(1)
}
let secret = Array(CommandLine.arguments[1].utf8)
guard secret.count >= 32 else {
    print("error: the secret looks too short — expected 64 hex characters")
    exit(1)
}

var lines: [String] = []
var current = "        "
for (index, byte) in secret.enumerated() {
    current += String(format: "0x%02X, ", byte ^ mask[index % mask.count])
    if (index + 1) % 12 == 0 {
        lines.append(String(current.dropLast()))
        current = "        "
    }
}
if current.trimmingCharacters(in: .whitespaces).isEmpty == false {
    lines.append(String(current.dropLast()))
}

print("    private static let maskedSecret: [UInt8] = [")
print(lines.joined(separator: "\n"))
print("    ]")
