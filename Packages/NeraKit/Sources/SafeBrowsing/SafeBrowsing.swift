// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import Networking

/// What a page was listed for (v5 `ThreatType`).
public enum SafeBrowsingThreat: Int, Sendable, Hashable, Comparable {
    /// Malware: no way past the warning.
    case malware = 1
    /// Phishing / deceptive site.
    case socialEngineering = 2
    /// Unwanted software.
    case unwantedSoftware = 3
    /// Android-only; never enforced on macOS.
    case potentiallyHarmfulApplication = 4

    /// Most severe first.
    public static func < (a: Self, b: Self) -> Bool { a.severity > b.severity }

    private var severity: Int {
        switch self {
        case .malware: 3
        case .socialEngineering: 2
        case .unwantedSoftware: 1
        case .potentiallyHarmfulApplication: 0
        }
    }
}

/// Why Safe Browsing couldn't do something.
public enum SafeBrowsingError: Error, Equatable, Sendable {
    /// The server's answer isn't valid protobuf.
    case malformedResponse
    /// A list with hashes longer than 4 bytes (not requested).
    case unsupportedHashLength
    /// A partial update doesn't fit the local list; the list is fetched in full next time.
    case inconsistentUpdate
    /// The updated list doesn't match the server's checksum; fetched in full next time.
    case checksumMismatch
    /// The server answered with an HTTP error.
    case http(Int)
}

/// How Safe Browsing reaches Google (a fake in tests).
public protocol SafeBrowsingTransport: Sendable {
    /// `GET /v5/hashList/{name}?version=…` (protobuf `HashList`).
    func hashList(name: String, version: Data?) async throws -> Data
    /// `GET /v5/hashes:search?hashPrefixes=…` (protobuf `SearchHashesResponse`); only 4-byte prefixes are ever sent.
    func searchHashes(prefixes: [Data]) async throws -> Data
}

/// The real transport: Google's Safe Browsing v5 API through Nera's allowlisted client. The key goes in a header,
/// never in a URL.
public struct GoogleSafeBrowsingTransport: SafeBrowsingTransport {
    private let key: String
    private let client: NeraHTTPClient

    /// A transport using `key` (restricted to the Safe Browsing API).
    public init(key: String, client: NeraHTTPClient = NeraHTTPClient()) {
        self.key = key
        self.client = client
    }

    /// Fetches a list (or the changes since `version`).
    public func hashList(name: String, version: Data?) async throws -> Data {
        var parts = URLComponents(string: "https://safebrowsing.googleapis.com/v5/hashList/\(name)")
        if let version { parts?.percentEncodedQuery = "version=" + Self.escaped(version.base64EncodedString()) }
        return try await get(parts?.url)
    }

    /// Asks for the full hashes behind some 4-byte prefixes.
    public func searchHashes(prefixes: [Data]) async throws -> Data {
        var parts = URLComponents(string: "https://safebrowsing.googleapis.com/v5/hashes:search")
        parts?.percentEncodedQuery = prefixes.map { "hashPrefixes=" + Self.escaped($0.prefix(4).base64EncodedString()) }
            .joined(separator: "&")
        return try await get(parts?.url)
    }

    /// Base64 for a query value: `+`, `/` and `=` escaped (a raw `+` would be read as a space).
    static func escaped(_ base64: String) -> String {
        base64.replacingOccurrences(of: "+", with: "%2B").replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "=", with: "%3D")
    }

    private func get(_ url: URL?) async throws -> Data {
        guard let url else { throw SafeBrowsingError.malformedResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
        let (data, response) = try await client.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SafeBrowsingError.http(status) }
        return data
    }
}

/// What a check found.
public enum SafeBrowsingVerdict: Equatable, Sendable {
    /// Not listed.
    case safe
    /// Listed (main frame).
    case threat(SafeBrowsingThreat)
    /// Google couldn't be asked: the page isn't blocked (fail open), and isn't held again for a few minutes.
    case unavailable
}

/// Google Safe Browsing v5 in Local List mode. Threat lists of 4-byte hash prefixes are kept on
/// this Mac and updated on the server's schedule. A page address never leaves the Mac: only when one of its
/// hashes' prefixes is in a local list are those 4-byte prefixes sent to Google, which answers with the full hashes
/// behind them. Google sees the Mac's IP address and Nera's API key on these requests.
///
/// ``holds(_:)`` answers synchronously from local data (the navigation policy calls it before any request);
/// ``verify(_:)`` asks Google when needed. State is guarded by a lock; network calls run outside it.
public final class SafeBrowsing: @unchecked Sendable {
    /// The lists checked on macOS: phishing, malware, unwanted software.
    public static let lists = ["se-4b", "mw-4b", "uws-4b"]
    /// How long a page that couldn't be checked passes without being held again.
    static let failOpenWindow: TimeInterval = 300

    private let directory: URL
    private let transport: any SafeBrowsingTransport
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    // Guarded by `lock`.
    private var prefixLists: [String: PrefixList] = [:]
    private var versions: [String: Data] = [:]
    private var nextUpdate = Date.distantPast
    private var failures = 0
    /// Full hashes the server confirmed, with the threats and when the answer expires.
    private var fullHashes: [Data: (threats: Set<SafeBrowsingThreat>, expires: Date)] = [:]
    /// Prefixes already searched, until when the answer holds (covers prefixes without any full hash too).
    private var searchedPrefixes: [UInt32: Date] = [:]
    /// Canonical URLs that couldn't be checked: not held again until the time given.
    private var failedOpen: [String: Date] = [:]
    private var updater: Task<Void, Never>?

    /// Safe Browsing keeping its lists in `directory`.
    public init(directory: URL, transport: any SafeBrowsingTransport, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.transport = transport
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in Self.lists {
            if let list = PrefixList(file: Self.file(name, in: directory)),
                let version = try? Data(contentsOf: directory.appending(path: "\(name).version"))
            {
                prefixLists[name] = list
                versions[name] = version
            }
        }
    }

    /// Prefixes held locally, per list (for Settings and tests).
    public var listSizes: [String: Int] { lock.withLock { prefixLists.mapValues(\.count) } }

    // MARK: Checking

    /// Whether `url` must wait for ``verify(_:)`` before it's requested: one of its hash prefixes is in a local list
    /// and there's no fresh answer saying it's safe (or a cached answer says it's listed). Local only; fast.
    public func holds(_ url: URL) -> Bool {
        guard let canonical = SafeBrowsingURL(url.absoluteString) else { return false }
        let hashes = canonical.fullHashes
        let date = now()
        return lock.withLock {
            if let pass = failedOpen[canonical.canonical], pass > date { return false }
            for hash in hashes where prefixLists.values.contains(where: { $0.contains(Self.prefix(hash)) }) {
                if (searchedPrefixes[Self.prefix(hash)] ?? .distantPast) <= date { return true }
                if let entry = fullHashes[hash], entry.expires > date, !entry.threats.isEmpty { return true }
            }
            return false
        }
    }

    /// Asks Google about `url`'s locally matching prefixes if needed, and gives the verdict. When Google can't be
    /// reached the page passes (fail open) and isn't held again for `failOpenWindow`.
    public func verify(_ url: URL) async -> SafeBrowsingVerdict {
        guard let canonical = SafeBrowsingURL(url.absoluteString) else { return .safe }
        let hashes = canonical.fullHashes
        let date = now()
        let (candidates, unknown) = lock.withLock { () -> ([Data], Set<UInt32>) in
            let candidates = hashes.filter { hash in prefixLists.values.contains { $0.contains(Self.prefix(hash)) } }
            let unknown = Set(candidates.map(Self.prefix)).filter { (searchedPrefixes[$0] ?? .distantPast) <= date }
            return (candidates, unknown)
        }
        guard !candidates.isEmpty else { return .safe }
        if !unknown.isEmpty {
            guard let data = try? await transport.searchHashes(prefixes: unknown.sorted().map(Self.bytes)),
                let response = try? HashSearchResponse(data)
            else {
                lock.withLock { failedOpen[canonical.canonical] = date.addingTimeInterval(Self.failOpenWindow) }
                return .unavailable
            }
            // At least a minute, so a zero cache duration can't make a page be held again and again.
            let expires = date.addingTimeInterval(min(max(response.cacheDuration, 60), 86_400))
            lock.withLock {
                pruneCaches(at: date)
                for match in response.matches where match.fullHash.count == 32 {
                    fullHashes[match.fullHash] = (match.threats, expires)
                }
                for prefix in unknown { searchedPrefixes[prefix] = expires }
            }
        }
        let threats = lock.withLock {
            candidates.flatMap { hash -> Set<SafeBrowsingThreat> in
                guard let entry = fullHashes[hash], entry.expires > date else { return [] }
                return entry.threats
            }
        }
        return threats.filter { $0 != .potentiallyHarmfulApplication }.min().map(SafeBrowsingVerdict.threat) ?? .safe
    }

    /// The most severe threat `url` is listed for, or nil (also when Google couldn't be asked).
    public func threat(for url: URL) async -> SafeBrowsingThreat? {
        if case .threat(let threat) = await verify(url) { return threat }
        return nil
    }

    /// Drops expired answers (called with the lock held).
    private func pruneCaches(at date: Date) {
        guard fullHashes.count + searchedPrefixes.count + failedOpen.count > 1_000 else { return }
        fullHashes = fullHashes.filter { $0.value.expires > date }
        searchedPrefixes = searchedPrefixes.filter { $0.value > date }
        failedOpen = failedOpen.filter { $0.value > date }
    }

    // MARK: Updating

    /// Keeps the lists updated in the background until ``stop()``.
    public func start() {
        lock.withLock {
            guard updater == nil else { return }
            updater = Task { [weak self] in
                while !Task.isCancelled {
                    guard let wait = await self?.updateIfDue() else { return }
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    /// Stops background updates.
    public func stop() {
        lock.withLock {
            updater?.cancel()
            updater = nil
        }
    }

    /// Updates every list if it's time; returns how long to wait before the next update (the server's minimum, or
    /// a growing backoff after failures: 15–30 minutes, doubling up to 24 hours).
    @discardableResult
    public func updateIfDue() async -> TimeInterval {
        let date = now()
        let due = lock.withLock { nextUpdate }
        guard date >= due else { return due.timeIntervalSince(date) }
        var wait: TimeInterval = 0
        var failed = false
        for name in Self.lists {
            do {
                wait = max(wait, try await update(name))
            } catch {
                failed = true
            }
        }
        return lock.withLock {
            if failed {
                failures += 1
                wait = min(Double(15 * 60) * pow(2, Double(failures - 1)) * Double.random(in: 1...2), 86_400)
            } else {
                failures = 0
                wait = max(wait, 60)  // the server's minimum, never a busy loop
            }
            nextUpdate = date.addingTimeInterval(wait)
            return wait
        }
    }

    private func update(_ name: String) async throws -> TimeInterval {
        let version = lock.withLock { versions[name] }
        let update: HashListUpdate
        do {
            update = try HashListUpdate(try await transport.hashList(name: name, version: version))
        } catch SafeBrowsingError.http(let status) where (400..<500).contains(status) && status != 429 {
            forgetVersion(name)  // the server rejects our version: ask for the whole list next time
            throw SafeBrowsingError.http(status)
        }
        let current = update.partial ? lock.withLock { prefixLists[name]?.values ?? [] } : []
        let values: [UInt32]
        do {
            values = try PrefixList.applying(update, to: current)
            guard update.checksum.isEmpty || PrefixList.checksum(values) == update.checksum else {
                throw SafeBrowsingError.checksumMismatch
            }
        } catch {
            forgetVersion(name)  // start over with a full list next time
            throw error
        }
        let list = try PrefixList.write(values, to: Self.file(name, in: directory))
        try update.version.write(to: directory.appending(path: "\(name).version"), options: .atomic)
        lock.withLock {
            prefixLists[name] = list
            versions[name] = update.version
        }
        return update.minimumWait
    }

    private func forgetVersion(_ name: String) {
        lock.withLock { versions[name] = nil }
        try? FileManager.default.removeItem(at: directory.appending(path: "\(name).version"))
    }

    // MARK: Helpers

    static func file(_ name: String, in directory: URL) -> URL { directory.appending(path: "\(name).prefixes") }

    static func prefix(_ hash: Data) -> UInt32 {
        hash.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func bytes(_ prefix: UInt32) -> Data {
        Data([UInt8(prefix >> 24), UInt8(prefix >> 16 & 0xFF), UInt8(prefix >> 8 & 0xFF), UInt8(prefix & 0xFF)])
    }
}
