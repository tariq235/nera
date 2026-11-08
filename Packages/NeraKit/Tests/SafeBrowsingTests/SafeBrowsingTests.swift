// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import Testing

@testable import SafeBrowsing

/// URL canonicalization: Google's published test vectors (Safe Browsing "URLs and Hashing").
@Suite("Safe Browsing URLs")
struct SafeBrowsingURLTests {
    @Test(arguments: [
        ("http://host/%25%32%35", "http://host/%25"),
        ("http://host/%25%32%35%25%32%35", "http://host/%25%25"),
        ("http://host/%2525252525252525", "http://host/%25"),
        ("http://host/asdf%25%32%35asd", "http://host/asdf%25asd"),
        ("http://host/%%%25%32%35asd%%", "http://host/%25%25%25asd%25%25"),
        ("http://www.google.com/", "http://www.google.com/"),
        (
            "http://%31%36%38%2e%31%38%38%2e%39%39%2e%32%36/%2E%73%65%63%75%72%65/%77%77%77%2E%65%62%61%79%2E%63%6F%6D/",
            "http://168.188.99.26/.secure/www.ebay.com/"
        ),
        (
            "http://host%23.com/%257Ea%2521b%2540c%2523d%2524e%25f%255E00%252611%252A22%252833%252944_55%252B",
            "http://host%23.com/~a!b@c%23d$e%25f^00&11*22(33)44_55+"
        ),
        ("http://3279880203/blah", "http://195.127.0.11/blah"),
        ("http://www.google.com/blah/..", "http://www.google.com/"),
        ("www.google.com/", "http://www.google.com/"),
        ("www.google.com", "http://www.google.com/"),
        ("http://www.evil.com/blah#frag", "http://www.evil.com/blah"),
        ("http://www.GOOgle.com/", "http://www.google.com/"),
        ("http://www.google.com.../", "http://www.google.com/"),
        ("http://www.google.com/foo\tbar\rbaz\n2", "http://www.google.com/foobarbaz2"),
        ("http://www.google.com/q?", "http://www.google.com/q?"),
        ("http://www.google.com/q?r?", "http://www.google.com/q?r?"),
        ("http://www.google.com/q?r?s", "http://www.google.com/q?r?s"),
        ("http://evil.com/foo#bar#baz", "http://evil.com/foo"),
        ("http://evil.com/foo;", "http://evil.com/foo;"),
        ("http://evil.com/foo?bar;", "http://evil.com/foo?bar;"),
        ("http://notrailingslash.com", "http://notrailingslash.com/"),
        ("http://www.gotaport.com:1234/", "http://www.gotaport.com/"),
        ("  http://www.google.com/  ", "http://www.google.com/"),
        ("http:// leadingspace.com/", "http://%20leadingspace.com/"),
        ("http://%20leadingspace.com/", "http://%20leadingspace.com/"),
        ("%20leadingspace.com/", "http://%20leadingspace.com/"),
        ("https://www.securesite.com/", "https://www.securesite.com/"),
        ("http://host.com/ab%23cd", "http://host.com/ab%23cd"),
        ("http://host.com//twoslashes?more//slashes", "http://host.com/twoslashes?more//slashes"),
        ("http://google.com/#frag", "http://google.com/"),
        ("http://user:pass@Example.COM/a", "http://example.com/a"),
        ("http://0x7f.1/", "http://127.0.0.1/"),
        ("http://evil.example/%FF%FE/login.html", "http://evil.example/%FF%FE/login.html"),
        ("http://evil.example/a/%FF/../b", "http://evil.example/a/b"),
    ])
    func canonicalizesLikeGoogle(_ input: String, _ expected: String) {
        #expect(SafeBrowsingURL(input)?.canonical == expected)
    }

    @Test func otherSchemesArentChecked() {
        #expect(SafeBrowsingURL("file:///etc/passwd") == nil)
        #expect(SafeBrowsingURL("chrome-extension://abc/page.html") == nil)
    }

    @Test func expressionsMatchTheSpecification() {
        #expect(
            Set(SafeBrowsingURL("http://a.b.com/1/2.html?param=1")!.expressions) == [
                "a.b.com/1/2.html?param=1", "a.b.com/1/2.html", "a.b.com/", "a.b.com/1/",
                "b.com/1/2.html?param=1", "b.com/1/2.html", "b.com/", "b.com/1/",
            ])
        #expect(
            Set(SafeBrowsingURL("http://a.b.c.d.e.f.com/1.html")!.expressions) == [
                "a.b.c.d.e.f.com/1.html", "a.b.c.d.e.f.com/", "c.d.e.f.com/1.html", "c.d.e.f.com/",
                "d.e.f.com/1.html", "d.e.f.com/", "e.f.com/1.html", "e.f.com/", "f.com/1.html", "f.com/",
            ])
        #expect(Set(SafeBrowsingURL("http://1.2.3.4/1/")!.expressions) == ["1.2.3.4/1/", "1.2.3.4/"])
        #expect(SafeBrowsingURL("http://a.b/1/2/3/4/5/6.html")!.expressions.count <= 30)
    }
}

/// Decoding real Safe Browsing v5 responses (fixtures fetched from Google on 2026-11-05).
@Suite("Safe Browsing wire format")
struct SafeBrowsingWireTests {
    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "pb", subdirectory: "Fixtures")))
    }

    @Test func aRealListDecodesToGooglesChecksum() throws {
        let update = try HashListUpdate(Self.fixture("se-4b-1024"))
        #expect(update.name == "se-4b" && !update.partial && update.additions.count == 1024)
        #expect(update.additions == update.additions.sorted())
        #expect(PrefixList.checksum(update.additions) == update.checksum, "Rice decoding and field numbers are right")
        #expect(update.minimumWait > 0)
    }

    @Test func aRealSearchAnswerNamesGooglesTestPhishingPage() throws {
        let response = try HashSearchResponse(Self.fixture("search-phishing-test-page"))
        let expression = Data(SHA256.hash(data: Data("testsafebrowsing.appspot.com/s/phishing.html".utf8)))
        let match = try #require(response.matches.first { $0.fullHash == expression })
        #expect(match.threats == [.socialEngineering])
        #expect(response.cacheDuration > 0)
    }

    @Test func malformedInputThrowsInsteadOfTrapping() {
        #expect(throws: SafeBrowsingError.self) { try HashListUpdate(Data([0x22, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F])) }
        // A length of 2^63 and up (doesn't fit in Int).
        #expect(throws: SafeBrowsingError.self) {
            try HashListUpdate(Data([0x22, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]))
        }
        #expect(throws: SafeBrowsingError.self) { try HashListUpdate(Data([0x0A])) }
        var random = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let bytes = (0..<Int.random(in: 0...64, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
            _ = try? HashListUpdate(Data(bytes))
            _ = try? HashSearchResponse(Data(bytes))
        }
    }
}

/// The service end to end with a fake Google: updates, partial updates, lookups, caching, failing open.
@Suite("Safe Browsing service")
struct SafeBrowsingServiceTests {
    /// Encodes protobuf the way Google does, for fake responses.
    enum Proto {
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

        /// Rice-encodes sorted values, choosing the parameter from the largest gap (like Google) so the unary
        /// quotients stay short.
        static func rice(_ values: [UInt32]) -> Data {
            guard let first = values.first else { return Data() }
            let largest = zip(values, values.dropFirst()).map { $1 - $0 }.max() ?? 0
            let k = max(0, (32 - largest.leadingZeroBitCount) - 2)
            var bits: [UInt8] = []
            for (a, b) in zip(values, values.dropFirst()) {
                let delta = b - a
                bits += Array(repeating: 1, count: Int(delta >> UInt32(k))) + [0]
                bits += (0..<k).map { UInt8(delta >> UInt32($0) & 1) }
            }
            var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
            for (i, bit) in bits.enumerated() where bit == 1 { bytes[i / 8] |= 1 << UInt8(i % 8) }
            return field(1, UInt64(first)) + field(2, UInt64(k)) + field(3, UInt64(values.count - 1)) + field(4, Data(bytes))
        }

        static func hashList(
            _ name: String, version: String, partial: Bool = false, additions: [UInt32], removals: [UInt32] = [],
            checksumOf full: [UInt32]
        ) -> Data {
            var d = field(1, Data(name.utf8)) + field(2, Data(version.utf8))
            if partial { d += field(3, 1) }
            if !additions.isEmpty { d += field(4, rice(additions)) }
            if !removals.isEmpty { d += field(5, rice(removals)) }
            return d + field(6, field(1, 1800)) + field(7, PrefixList.checksum(full))
        }
    }

    final class FakeGoogle: SafeBrowsingTransport, @unchecked Sendable {
        var lists: [String: [Data]] = [:]
        var requestedVersions: [String: [Data?]] = [:]
        var searchAnswer = Data()
        var searches: [[Data]] = []
        var failSearch = false
        let lock = NSLock()

        func hashList(name: String, version: Data?) async throws -> Data {
            try lock.withLock {
                requestedVersions[name, default: []].append(version)
                guard var queue = lists[name], !queue.isEmpty else { throw SafeBrowsingError.http(503) }
                let next = queue.removeFirst()
                lists[name] = queue.isEmpty ? [next] : queue
                return next
            }
        }

        func searchHashes(prefixes: [Data]) async throws -> Data {
            try lock.withLock {
                searches.append(prefixes)
                if failSearch { throw SafeBrowsingError.http(503) }
                return searchAnswer
            }
        }
    }

    final class TestClock: @unchecked Sendable {
        var now = Date()
    }

    let phishing = URL(string: "https://bad.example/login.html?x=1")!
    var phishingHash: Data { Data(SHA256.hash(data: Data("bad.example/login.html?x=1".utf8))) }

    func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sb-test-\(UUID().uuidString)")
    }

    func google(listing prefix: UInt32) -> FakeGoogle {
        let fake = FakeGoogle()
        let se = [UInt32(5), prefix, 0xFFFF_FFF0].sorted()
        fake.lists["se-4b"] = [Proto.hashList("se-4b", version: "v1", additions: se, checksumOf: se)]
        fake.lists["mw-4b"] = [Proto.hashList("mw-4b", version: "v1", additions: [7], checksumOf: [7])]
        fake.lists["uws-4b"] = [Proto.hashList("uws-4b", version: "v1", additions: [9], checksumOf: [9])]
        let detail = Proto.field(1, 2)  // SOCIAL_ENGINEERING
        fake.searchAnswer =
            Proto.field(1, Proto.field(1, phishingHash) + Proto.field(2, detail)) + Proto.field(2, Proto.field(1, 300))
        return fake
    }

    @Test func aListedPageIsFoundAndOnlyItsPrefixLeavesTheMac() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        let sb = SafeBrowsing(directory: directory(), transport: fake)
        await sb.updateIfDue()
        #expect(sb.listSizes == ["se-4b": 3, "mw-4b": 1, "uws-4b": 1])
        #expect(await sb.threat(for: phishing) == .socialEngineering)
        #expect(fake.searches == [[SafeBrowsing.bytes(SafeBrowsing.prefix(phishingHash))]], "4 bytes, nothing else")
        #expect(await sb.threat(for: phishing) == .socialEngineering)
        #expect(fake.searches.count == 1, "the answer is cached for its cache duration")
        #expect(await sb.threat(for: URL(string: "https://good.example/")!) == nil)
        #expect(fake.searches.count == 1, "no local match, no request")
    }

    @Test func aPrefixMatchWithoutAFullHashIsSafe() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        fake.searchAnswer = Proto.field(2, Proto.field(1, 300))  // no full hashes
        let sb = SafeBrowsing(directory: directory(), transport: fake)
        await sb.updateIfDue()
        #expect(await sb.threat(for: phishing) == nil)
    }

    @Test func whenGoogleCantBeReachedPagesArentBlockedAndNothingIsCached() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        fake.failSearch = true
        let sb = SafeBrowsing(directory: directory(), transport: fake)
        await sb.updateIfDue()
        #expect(await sb.threat(for: phishing) == nil)
        fake.failSearch = false
        #expect(await sb.threat(for: phishing) == .socialEngineering, "asked again once Google answers")
    }

    @Test func partialUpdatesRemoveThenAddAndAreVerified() async throws {
        let fake = google(listing: 100)
        let dir = directory()
        // v1: [5, 100, 0xFFFFFFF0]; v2 removes index 1 (100) and adds 50, 200.
        let after: [UInt32] = [5, 50, 200, 0xFFFF_FFF0]
        fake.lists["se-4b"]!.append(
            Proto.hashList("se-4b", version: "v2", partial: true, additions: [50, 200], removals: [1], checksumOf: after))
        let clock = TestClock()
        let sb = SafeBrowsing(directory: dir, transport: fake, now: { clock.now })
        await sb.updateIfDue()
        clock.now += 3600
        await sb.updateIfDue()
        #expect(fake.requestedVersions["se-4b"] == [nil, Data("v1".utf8)])
        #expect(sb.listSizes["se-4b"] == 4)
        // The lists survive a restart (memory-mapped files).
        let reopened = SafeBrowsing(directory: dir, transport: fake)
        #expect(reopened.listSizes["se-4b"] == 4)
    }

    @Test func aChecksumMismatchStartsOverWithAFullList() async throws {
        let fake = google(listing: 100)
        fake.lists["se-4b"]!.append(
            Proto.hashList("se-4b", version: "v2", partial: true, additions: [50], checksumOf: [1, 2, 3]))
        let clock = TestClock()
        let sb = SafeBrowsing(directory: directory(), transport: fake, now: { clock.now })
        await sb.updateIfDue()
        clock.now += 3600
        let wait = await sb.updateIfDue()
        #expect(wait >= 15 * 60, "backs off after a failure")
        clock.now += wait + 1
        await sb.updateIfDue()
        #expect(fake.requestedVersions["se-4b"]?.last == .some(nil), "the next request asks for the full list")
    }

    @Test func theGateAnswersLocallyBeforeAnyRequest() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        let sb = SafeBrowsing(directory: directory(), transport: fake)
        await sb.updateIfDue()
        #expect(sb.holds(phishing), "a local prefix match is held")
        #expect(!sb.holds(URL(string: "https://good.example/")!))
        #expect(fake.searches.isEmpty, "deciding needs no network")
        #expect(await sb.verify(phishing) == .threat(.socialEngineering))
        #expect(sb.holds(phishing), "a listed page stays held (its warning is cached)")
    }

    @Test func whenGoogleCantBeAskedThePagePassesAndIsntHeldAgain() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        fake.failSearch = true
        let sb = SafeBrowsing(directory: directory(), transport: fake)
        await sb.updateIfDue()
        #expect(await sb.verify(phishing) == .unavailable)
        #expect(!sb.holds(phishing), "no stop-and-reload loop while Google is unreachable")
    }

    @Test func aZeroCacheDurationStillHoldsTheAnswerForAMinute() async throws {
        let fake = google(listing: SafeBrowsing.prefix(phishingHash))
        fake.searchAnswer = Proto.field(2, Data())  // no matches, cacheDuration 0
        let clock = TestClock()
        let sb = SafeBrowsing(directory: directory(), transport: fake, now: { clock.now })
        await sb.updateIfDue()
        #expect(await sb.verify(phishing) == .safe)
        #expect(!sb.holds(phishing))
        clock.now += 61
        #expect(sb.holds(phishing))
    }

    @Test func aRejectedVersionAsksForTheWholeListNextTime() async throws {
        let fake = google(listing: 100)
        final class Rejecting: SafeBrowsingTransport, @unchecked Sendable {
            let inner: FakeGoogle
            var reject = false
            init(_ inner: FakeGoogle) { self.inner = inner }
            func hashList(name: String, version: Data?) async throws -> Data {
                if reject, version != nil { throw SafeBrowsingError.http(400) }
                return try await inner.hashList(name: name, version: version)
            }
            func searchHashes(prefixes: [Data]) async throws -> Data { try await inner.searchHashes(prefixes: prefixes) }
        }
        let transport = Rejecting(fake)
        let clock = TestClock()
        let sb = SafeBrowsing(directory: directory(), transport: transport, now: { clock.now })
        await sb.updateIfDue()
        transport.reject = true
        clock.now += 3600
        await sb.updateIfDue()
        transport.reject = false
        clock.now += 86_401
        await sb.updateIfDue()
        #expect(fake.requestedVersions["se-4b"]?.last == .some(nil))
    }

    @Test func queryValuesAreEscaped() {
        #expect(GoogleSafeBrowsingTransport.escaped("ab+c/d==") == "ab%2Bc%2Fd%3D%3D")
    }

    @Test func updatesFollowTheServersSchedule() async throws {
        let clock = TestClock()
        let fake = google(listing: 1)
        let sb = SafeBrowsing(directory: directory(), transport: fake, now: { clock.now })
        let wait = await sb.updateIfDue()
        #expect(wait == 1800)
        clock.now += 60
        _ = await sb.updateIfDue()
        #expect(fake.requestedVersions["se-4b"]?.count == 1, "not before the server's minimum wait")
    }
}

/// Against Google itself, with the real lists and Google's test pages. Opt-in (needs the key and the network):
/// `NERA_SAFE_BROWSING_KEY=$(security find-generic-password -s "Nera Safe Browsing Key" -a nera -w) swift test --filter Live`
@Suite("Safe Browsing live", .enabled(if: ProcessInfo.processInfo.environment["NERA_SAFE_BROWSING_KEY"] != nil))
struct SafeBrowsingLiveTests {
    @Test func googlesTestPagesAreFlaggedAndOrdinaryPagesArent() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["NERA_SAFE_BROWSING_KEY"])
        let dir = FileManager.default.temporaryDirectory.appending(path: "sb-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sb = SafeBrowsing(directory: dir, transport: GoogleSafeBrowsingTransport(key: key))
        let wait = await sb.updateIfDue()
        let sizes = sb.listSizes
        #expect(sizes.count == 3 && sizes.values.allSatisfy { $0 > 1000 }, "lists downloaded and verified: \(sizes)")
        #expect(wait >= 60)
        let base = "https://testsafebrowsing.appspot.com/s/"
        #expect(await sb.threat(for: URL(string: base + "phishing.html")!) == .socialEngineering)
        #expect(await sb.threat(for: URL(string: base + "malware.html")!) == .malware)
        #expect(await sb.threat(for: URL(string: base + "unwanted.html")!) == .unwantedSoftware)
        #expect(await sb.threat(for: URL(string: "https://www.apple.com/")!) == nil)
    }
}
