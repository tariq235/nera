// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import Networking

/// Finds, downloads and verifies updates. Installing the verified file is a separate step (ADR-0011).
/// Every request goes through `NeraHTTPClient`, so the feed and download hosts must be on Nera's allowlist.
public struct UpdateChecker: Sendable {
    /// Where the feed lives.
    public let feedURL: URL
    /// The installed build number.
    public let currentBuild: Int
    /// The user's channel.
    public let channel: UpdateChannel
    /// This installation's staged-rollout group, stable for its lifetime.
    public let rolloutGroup: Int
    let verifier: UpdateVerifier
    let client: NeraHTTPClient

    /// Creates a checker. Returns nil when the app has no feed or key configured (development builds).
    public init?(
        feedURL: URL?, publicKeyBase64: String?, currentBuild: Int, channel: UpdateChannel, rolloutGroup: Int,
        client: NeraHTTPClient = NeraHTTPClient()
    ) {
        guard let feedURL, let key = publicKeyBase64.flatMap(UpdateVerifier.init(publicKeyBase64:)) else { return nil }
        self.feedURL = feedURL
        self.currentBuild = currentBuild
        self.channel = channel
        self.rolloutGroup = rolloutGroup
        self.verifier = key
        self.client = client
    }

    /// The update this installation should take now, if any.
    public func check(os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, now: Date = Date()) async throws
        -> AppcastItem?
    {
        let (data, _) = try await client.data(for: URLRequest(url: feedURL))
        return UpdatePolicy.best(
            try Appcast.parse(data), currentBuild: currentBuild, channel: channel, os: os, rolloutGroup: rolloutGroup, now: now)
    }

    /// Downloads `item` and returns its contents only if the size and signature check out.
    public func download(_ item: AppcastItem) async throws -> Data {
        let (data, _) = try await client.data(for: URLRequest(url: item.url))
        try verifier.verify(data, for: item)
        return data
    }
}
