// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import CryptoKit
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import SafeBrowsing
import Storage
import Testing

@testable import BrowserShell

/// Safe Browsing in the app: a Chromium page whose address is listed is held, then replaced by a warning.
@MainActor
@Suite("Dangerous sites")
struct SafeBrowsingIntegrationTests {
    /// A fake Google listing one phishing and one malware address.
    final class FakeGoogle: SafeBrowsingTransport, @unchecked Sendable {
        static func varint(_ v: UInt64) -> Data {
            var v = v
            var out = Data()
            repeat {
                var b = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 { b |= 0x80 }
                out.append(b)
            } while v != 0
            return out
        }
        static func field(_ n: Int, _ v: UInt64) -> Data { varint(UInt64(n << 3)) + varint(v) }
        static func field(_ n: Int, _ d: Data) -> Data { varint(UInt64(n << 3 | 2)) + varint(UInt64(d.count)) + d }
        static func hash(_ expression: String) -> Data { Data(SHA256.hash(data: Data(expression.utf8))) }
        static func prefix(_ hash: Data) -> UInt32 { hash.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }

        let listed: [(hash: Data, threat: Int)] = [
            (hash("phish.example/login"), 2), (hash("malware.example/"), 1),
        ]
        var searches = 0
        let lock = NSLock()

        /// One list holding the listed prefixes plus a prefix-only collision ("collision.example/").
        func hashList(name: String, version: Data?) async throws -> Data {
            var values = listed.map { Self.prefix($0.hash) } + [Self.prefix(Self.hash("collision.example/"))]
            values.sort()
            guard name == "se-4b" else { return Self.field(1, Data(name.utf8)) + Self.field(2, Data("v".utf8)) }
            // Golomb-Rice with k = 28: the quotient in unary (ones, then a zero), then 28 remainder bits.
            var bits: [UInt8] = []
            for (a, b) in zip(values, values.dropFirst()) {
                let delta = b - a
                bits += Array(repeating: 1, count: Int(delta >> 28)) + [0] + (0..<28).map { UInt8(delta >> UInt32($0) & 1) }
            }
            var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
            for (i, bit) in bits.enumerated() where bit == 1 { bytes[i / 8] |= 1 << UInt8(i % 8) }
            let rice =
                Self.field(1, UInt64(values[0])) + Self.field(2, 28) + Self.field(3, UInt64(values.count - 1)) + Self.field(4, Data(bytes))
            return Self.field(1, Data(name.utf8)) + Self.field(2, Data("v".utf8)) + Self.field(4, rice) + Self.field(6, Self.field(1, 1800))
        }

        func searchHashes(prefixes: [Data]) async throws -> Data {
            lock.withLock { searches += 1 }
            var out = Data()
            for entry in listed where prefixes.contains(entry.hash.prefix(4)) {
                out += Self.field(1, Self.field(1, entry.hash) + Self.field(2, Self.field(1, UInt64(entry.threat))))
            }
            return out + Self.field(2, Self.field(1, 300))
        }
    }

    let chromium = FakeEngine(id: "chromium")
    let webKit = FakeEngine(id: "webkit")
    let google = FakeGoogle()

    func model() async -> AppModel {
        let m = AppModel(
            store: .load(persistence: InMemoryStore()), registry: EngineRegistry([chromium, webKit]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))
        let dir = FileManager.default.temporaryDirectory.appending(path: "sb-app-\(UUID().uuidString)")
        m.configureSafeBrowsing(directory: dir, transport: google)
        await m.safety.service?.updateIfDue()
        return m
    }

    /// Opens a tab, and plays what the engine does: ask the page's policy, and report a held navigation.
    func open(_ m: AppModel, _ address: String) throws -> FakePage {
        let url = URL(string: address)!
        m.send(.tab(.open(url, .newTab)))
        let page = try #require(m.selectedPage as? FakePage)
        navigate(page, to: url)
        return page
    }

    func navigate(_ page: FakePage, to url: URL) {
        let policy = (page.engineID == "chromium" ? chromium : webKit).configurations.last { $0.id == page.id }?.policy
        if case .block(let reason) = policy?.decide(url, trigger: .linkClick) {
            page.simulate(.navigationBlocked(url, reason))
        } else {
            page.simulate(.navigationStarted(url))
        }
    }

    func settle(_ m: AppModel, until done: () -> Bool) async throws {
        for _ in 0..<100 where !done() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aPhishingPageIsStoppedAndWarnedAbout() async throws {
        let m = await model()
        let page = try open(m, "https://phish.example/login")
        try await settle(m) { m.currentDangerousSite != nil }
        #expect(m.currentDangerousSite?.threat == .socialEngineering)
        #expect(page.loads.count == 1, "never requested: the initial load was held by the policy")
        // Continue anyway: loaded, and not held again this session.
        m.continueToDangerousSite(page.id)
        #expect(m.currentDangerousSite == nil && page.loads.last?.host() == "phish.example")
        navigate(page, to: URL(string: "https://phish.example/login")!)
        try await Task.sleep(for: .milliseconds(50))
        #expect(m.currentDangerousSite == nil)
    }

    @Test func malwareHasNoWayPast() async throws {
        let m = await model()
        let page = try open(m, "https://malware.example/")
        try await settle(m) { m.currentDangerousSite != nil }
        #expect(m.currentDangerousSite?.threat == .malware)
        m.continueToDangerousSite(page.id)
        #expect(m.currentDangerousSite?.threat == .malware, "Continue anyway does nothing for malware")
        let tabs = m.state.spaces.flatMap(m.state.orderedTabs(in:)).count
        m.leaveDangerousSite(page.id)  // no history: the tab closes
        #expect(m.state.spaces.flatMap(m.state.orderedTabs(in:)).count == tabs - 1)
    }

    @Test func aPrefixCollisionIsReloadedOnceGoogleSaysItsSafe() async throws {
        let m = await model()
        let page = try open(m, "https://collision.example/")
        try await settle(m) { google.searches > 0 && page.loads.count >= 2 }
        #expect(m.currentDangerousSite == nil)
        #expect(page.loads.count == 2, "loaded once Google said it's safe")
        navigate(page, to: URL(string: "https://collision.example/")!)
        #expect(m.pages.heldNavigations[page.id] == nil, "not held again: the answer is cached")
    }

    @Test func ordinaryPagesAreNeverHeldOrSentAnywhere() async throws {
        let m = await model()
        _ = try open(m, "https://www.apple.com/")
        try await Task.sleep(for: .milliseconds(50))
        #expect(m.pages.heldNavigations.isEmpty && google.searches == 0 && m.currentDangerousSite == nil)
    }

    @Test func aLateAnswerDoesntTouchAPageThatMovedOn() async throws {
        let m = await model()
        let page = try open(m, "https://collision.example/")
        navigate(page, to: URL(string: "https://www.apple.com/")!)  // the user went elsewhere first
        try await settle(m) { google.searches > 0 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(page.loads.count == 1, "the old address isn't loaded over the new one")
        #expect(m.safety.dangerousSites[page.id] == nil)
    }

    @Test func webKitPagesAreLeftToApplesWarningAndTheSettingTurnsItOff() async throws {
        let m = await model()
        let profile = try #require(m.state.currentProfile)
        m.send(.library(.setSiteEngine(profileID: profile.id, site: "phish.example", .webKit)))
        let page = try open(m, "https://phish.example/login")
        #expect(page.engineID == "webkit")
        try await Task.sleep(for: .milliseconds(50))
        #expect(m.currentDangerousSite == nil && google.searches == 0)
        m.warnsAboutDangerousSites = false
        defer { m.warnsAboutDangerousSites = true }
        #expect(m.safety.service == nil)
    }
}
