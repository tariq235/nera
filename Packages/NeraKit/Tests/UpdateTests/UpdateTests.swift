// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import Networking
import Testing

@testable import Update

/// Update feed, channel/rollout policy and signature checks (REL-007, REL-012).
@Suite("Updates")
struct UpdateTests {
    static let key = Curve25519.Signing.PrivateKey()
    static var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    static let payload = Data("Nera 1.2.0 disk image".utf8)
    static var signature: String { (try! key.signature(for: payload)).base64EncodedString() }
    static let monday = Date(timeIntervalSince1970: 1_800_000_000)

    static func feed(_ items: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel><title>Nera</title>\(items)</channel>
            </rss>
            """.utf8)
    }

    static func item(
        build: Int, channel: String? = nil, url: String = "https://updates.example/Nera.dmg", extra: String = "", signed: Bool = true
    )
        -> String
    {
        """
        <item>
          <title>\(build)</title>
          <pubDate>Fri, 15 Jan 2027 08:00:00 +0000</pubDate>
          <sparkle:version>\(build)</sparkle:version>
          <sparkle:shortVersionString>1.\(build).0</sparkle:shortVersionString>
          \(channel.map { "<sparkle:channel>\($0)</sparkle:channel>" } ?? "")
          \(extra)
          <enclosure url="\(url)" length="\(payload.count)" type="application/octet-stream" \(signed ? "sparkle:edSignature=\"\(signature)\"" : "")/>
        </item>
        """
    }

    @Test func parsesSparkleFeedsAndDropsUnsafeItems() throws {
        let items = try Appcast.parse(
            Self.feed(
                Self.item(build: 10, extra: "<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion><sparkle:criticalUpdate/>")
                    + Self.item(build: 11, channel: "beta")
                    + Self.item(build: 12, url: "http://updates.example/Nera.dmg")  // not HTTPS
                    + Self.item(build: 13, signed: false)  // unsigned
                    + Self.item(build: 14, channel: "canary")))  // unknown channel
        #expect(items.map(\.build) == [10, 11])
        #expect(items[0].isCritical && items[0].channel == .stable && items[0].minimumSystemVersion?.majorVersion == 15)
        #expect(items[0].publishedAt != nil)
        #expect(items[1].channel == .beta && items[1].displayVersion == "1.11.0")
        #expect(throws: UpdateError.malformedFeed) { try Appcast.parse(Data("<html>".utf8)) }
    }

    /// The feed written by scripts/release/make-appcast.py parses as intended (the two must stay in sync).
    @Test func feedsWrittenByTheReleaseScriptParse() throws {
        let url = try #require(Bundle.module.url(forResource: "appcast-from-make-appcast", withExtension: "xml", subdirectory: "Fixtures"))
        let items = try Appcast.parse(Data(contentsOf: url))
        #expect(items.map(\.build) == [3, 2])
        #expect(items[0].channel == .beta && items[0].isCritical)
        #expect(items[1].channel == .stable && items[1].rolloutInterval == 86_400)
        #expect(items.allSatisfy { $0.publishedAt != nil && $0.minimumSystemVersion?.majorVersion == 15 })
    }

    @Test func externalEntitiesAreNeverResolved() throws {
        let xxe = Data(
            """
            <?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>
            <rss><channel><item><sparkle:version>&x;</sparkle:version></item></channel></rss>
            """.utf8)
        #expect((try? Appcast.parse(xxe))?.isEmpty ?? true)
    }

    @Test func channelsAcceptMoreStableReleases() {
        #expect(UpdateChannel.stable.accepts == [.stable])
        #expect(UpdateChannel.beta.accepts == [.stable, .beta])
        #expect(UpdateChannel.nightly.accepts == Set(UpdateChannel.allCases))
    }

    func item(_ build: Int, _ channel: UpdateChannel = .stable, rollout: TimeInterval? = nil, critical: Bool = false, minOS: Int? = nil)
        -> AppcastItem
    {
        AppcastItem(
            build: build, displayVersion: "\(build)", channel: channel, url: URL(string: "https://u.example/\(build)")!, length: 1,
            edSignature: "x",
            minimumSystemVersion: minOS.map { OperatingSystemVersion(majorVersion: $0, minorVersion: 0, patchVersion: 0) },
            publishedAt: Self.monday, rolloutInterval: rollout, isCritical: critical)
    }

    @Test func picksTheNewestFittingUpdate() {
        let os = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        let items = [item(5), item(7, .beta), item(9, .nightly), item(8, minOS: 27)]
        func best(_ channel: UpdateChannel, current: Int = 1) -> Int? {
            UpdatePolicy.best(items, currentBuild: current, channel: channel, os: os, rolloutGroup: 0, now: Self.monday)?.build
        }
        #expect(best(.stable) == 5)
        #expect(best(.beta) == 7)
        #expect(best(.nightly) == 9)
        #expect(best(.stable, current: 5) == nil, "never offers the installed build or older")
    }

    @Test func stagedRolloutReachesGroupsDayByDay() {
        let os = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        let day: TimeInterval = 86_400
        let staged = [item(5, rollout: day)]
        func offered(group: Int, after days: Double) -> Bool {
            UpdatePolicy.best(staged, currentBuild: 1, channel: .stable, os: os, rolloutGroup: group, now: Self.monday + days * day) != nil
        }
        #expect(offered(group: 0, after: 0))
        #expect(!offered(group: 3, after: 2.5))
        #expect(offered(group: 3, after: 3))
        #expect(offered(group: 6, after: 6))
        let critical = [item(5, rollout: day, critical: true)]
        #expect(UpdatePolicy.best(critical, currentBuild: 1, channel: .stable, os: os, rolloutGroup: 6, now: Self.monday) != nil)
    }

    @Test func onlyCorrectlySignedFilesPass() throws {
        let verifier = try #require(UpdateVerifier(publicKeyBase64: Self.publicKey))
        let item = try #require(try Appcast.parse(Self.feed(Self.item(build: 2))).first)
        try verifier.verify(Self.payload, for: item)

        var tampered = Self.payload
        tampered[0] ^= 0x01
        #expect(throws: UpdateError.badSignature) { try verifier.verify(tampered, for: item) }
        #expect(throws: UpdateError.wrongLength) { try verifier.verify(Self.payload + Data([0]), for: item) }

        let other = try #require(
            UpdateVerifier(publicKeyBase64: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        #expect(throws: UpdateError.badSignature) { try other.verify(Self.payload, for: item) }
        #expect(UpdateVerifier(publicKeyBase64: "not a key") == nil)
    }

    @Test func eitherTheCurrentOrTheStandbyKeyIsAccepted() throws {
        let item = try #require(try Appcast.parse(Self.feed(Self.item(build: 2))).first)
        let standby = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let both = try #require(UpdateVerifier(publicKeyBase64: "\(standby), \(Self.publicKey)"))
        try both.verify(Self.payload, for: item)  // signed with the second listed key
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let wrong = try #require(UpdateVerifier(publicKeyBase64: "\(standby),\(stranger)"))
        #expect(throws: UpdateError.badSignature) { try wrong.verify(Self.payload, for: item) }
        #expect(UpdateVerifier(publicKeyBase64: "\(standby),garbage") == nil, "a broken key list isn't half-trusted")
    }

    @Test func checkerNeedsAKeyAndOnlyTalksToAllowlistedHosts() async {
        #expect(
            UpdateChecker(
                feedURL: URL(string: "https://updates.example/appcast.xml"), publicKeyBase64: nil, currentBuild: 1, channel: .stable,
                rolloutGroup: 0) == nil)
        let checker = UpdateChecker(
            feedURL: URL(string: "https://updates.example/appcast.xml"), publicKeyBase64: Self.publicKey, currentBuild: 1,
            channel: .stable, rolloutGroup: 0, client: NeraHTTPClient(allowlist: .nera))
        await #expect(throws: NetworkPolicyError.hostNotAllowed("updates.example")) { try await checker?.check() }
    }

    @Test func damagedFeedsNeverCrash() {
        var bytes = [UInt8](Self.feed(Self.item(build: 3) + Self.item(build: 4, channel: "beta")))
        var seed: UInt64 = 7
        for _ in 0..<1500 {
            var copy = bytes
            for _ in 0..<4 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                copy[Int(seed >> 33) % copy.count] = UInt8(truncatingIfNeeded: seed >> 17)
            }
            _ = try? Appcast.parse(Data(copy))
        }
        bytes.removeAll()
    }
}

@Suite("Release check")
struct ReleaseCheckTests {
    func json(_ tag: String, draft: Bool = false, url: String = "https://github.com/tariq235/nera/releases/tag/v0.2.0") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "html_url": url])
    }

    @Test func newerReleasesOnly() {
        #expect(ReleaseCheck.parse(json("v0.2.0"), currentVersion: "0.1.0")?.version == "0.2.0")
        #expect(ReleaseCheck.parse(json("v0.1.0"), currentVersion: "0.1.0") == nil)
        #expect(ReleaseCheck.parse(json("v0.2.0", draft: true), currentVersion: "0.1.0") == nil)
        #expect(ReleaseCheck.parse(json("v9.0.0", url: "https://evil.example/x"), currentVersion: "0.1.0") == nil, "only github.com pages")
        #expect(ReleaseCheck.parse(Data("{}".utf8), currentVersion: "0.1.0") == nil)
    }

    @Test func versionsCompareNumerically() {
        #expect(ReleaseCheck.isNewer("0.10.0", than: "0.9.3"))
        #expect(ReleaseCheck.isNewer("1.0", than: "0.99.99"))
        #expect(!ReleaseCheck.isNewer("0.1.0", than: "0.1"))
        #expect(!ReleaseCheck.isNewer("0.1.0-beta.2", than: "0.1.0"))
    }
}
