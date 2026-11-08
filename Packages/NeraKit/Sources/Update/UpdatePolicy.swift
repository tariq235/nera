// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
public import Foundation

/// Which update, if any, this installation should take.
public enum UpdatePolicy {
    /// Number of staged-rollout groups (Sparkle uses 7: one per interval).
    public static let rolloutGroups = 7

    /// The newest item newer than `currentBuild` that fits this channel, this macOS, and this installation's
    /// rollout group (0 ..< ``rolloutGroups``). Critical updates skip the rollout.
    public static func best(
        _ items: [AppcastItem], currentBuild: Int, channel: UpdateChannel, os: OperatingSystemVersion, rolloutGroup: Int, now: Date
    ) -> AppcastItem? {
        items
            .filter { $0.build > currentBuild && channel.accepts.contains($0.channel) }
            .filter { item in item.minimumSystemVersion.map { !isOlder(os, than: $0) } ?? true }
            .filter { item in
                guard !item.isCritical, let interval = item.rolloutInterval, let start = item.publishedAt else { return true }
                return now >= start.addingTimeInterval(interval * Double(max(0, min(rolloutGroup, rolloutGroups - 1))))
            }
            .max { $0.build < $1.build }
    }

    static func isOlder(_ a: OperatingSystemVersion, than b: OperatingSystemVersion) -> Bool {
        (a.majorVersion, a.minorVersion, a.patchVersion) < (b.majorVersion, b.minorVersion, b.patchVersion)
    }
}

/// Checks a downloaded update against the Ed25519 public key built into the app (REL-007). Nothing is installed
/// unless this passes.
public struct UpdateVerifier: Sendable {
    let keys: [Curve25519.Signing.PublicKey]

    /// Creates a verifier from base64 public keys (`SUPublicEDKey` format, 32 raw bytes), comma-separated: the
    /// current signing key and a standby one, so the signing key can be replaced without stranding installs
    /// (docs/release/update-signing-key.md). Nil unless every listed key is valid.
    public init?(publicKeyBase64: String) {
        let parts = publicKeyBase64.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let keys = parts.compactMap { Data(base64Encoded: $0).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } }
        guard !keys.isEmpty, keys.count == parts.count else { return nil }
        self.keys = keys
    }

    /// Throws unless `data` is exactly the item's length and carries a valid signature from one of the keys.
    public func verify(_ data: Data, for item: AppcastItem) throws {
        guard data.count == item.length else { throw UpdateError.wrongLength }
        guard let signature = Data(base64Encoded: item.edSignature), keys.contains(where: { $0.isValidSignature(signature, for: data) })
        else { throw UpdateError.badSignature }
    }
}
