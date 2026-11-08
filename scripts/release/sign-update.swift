#!/usr/bin/env swift
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ed25519 signing for Nera updates (REL-007). Same key format as Sparkle 2: a base64 32-byte seed (private)
// and a base64 32-byte public key (SUPublicEDKey). Uses Apple's CryptoKit; no third-party tools.
//
//   swift scripts/release/sign-update.swift generate-keys      → prints a new key pair (store the private key
//                                                               ONLY in the `release` environment secret)
//   SPARKLE_ED_PRIVATE_KEY=… swift scripts/release/sign-update.swift sign <file>
//                                                             → prints: <base64 signature> <length>
//   swift scripts/release/sign-update.swift verify <file> <signature> <public key>
//   … | swift scripts/release/sign-update.swift public-key    → the public key of the private key on stdin (backups)
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "generate-keys":
    let key = Curve25519.Signing.PrivateKey()
    print("private (secret SPARKLE_ED_PRIVATE_KEY): \(key.rawRepresentation.base64EncodedString())")
    print("public  (Info.plist NeraUpdatePublicKey): \(key.publicKey.rawRepresentation.base64EncodedString())")
case "sign":
    guard args.count == 2, let path = args.last else { fail("usage: sign <file>") }
    guard let seed = ProcessInfo.processInfo.environment["SPARKLE_ED_PRIVATE_KEY"].flatMap({ Data(base64Encoded: $0) }),
        let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else { fail("SPARKLE_ED_PRIVATE_KEY is missing or not a base64 32-byte key") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    guard let signature = try? key.signature(for: data) else { fail("signing failed") }
    print("\(signature.base64EncodedString()) \(data.count)")
case "verify":
    let a = Array(args)
    guard a.count == 4, let data = FileManager.default.contents(atPath: a[1]),
        let sig = Data(base64Encoded: a[2]), let pub = Data(base64Encoded: a[3]),
        let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pub)
    else { fail("usage: verify <file> <signature> <public key>") }
    if key.isValidSignature(sig, for: data) { print("✔ signature valid") } else { fail("✘ signature INVALID") }
case "public-key":
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let seed = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
        let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else { fail("stdin isn't a base64 32-byte private key") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
default:
    fail("usage: sign-update.swift generate-keys | sign <file> | verify <file> <signature> <public key> | public-key")
}
