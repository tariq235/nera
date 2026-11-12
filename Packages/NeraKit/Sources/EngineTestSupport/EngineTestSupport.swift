// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
public import Foundation
public import Observation

/// A scriptable engine for testing engine-neutral code (PageLifecycle, shell logic).
@MainActor
public final class FakeEngine: BrowserEngine {
    /// Identity; set `isAvailable` to test registry fallback.
    public var descriptor: EngineDescriptor
    /// Declares every capability.
    public let capabilities: EngineCapabilities = Set(EngineCapability.allCases)
    /// Every page made, by ID.
    public private(set) var pages: [UUID: FakePage] = [:]
    /// Every configuration passed to ``makePage(_:delegate:)``, in order.
    public private(set) var configurations: [PageConfiguration] = []
    /// Scopes whose data was removed.
    public private(set) var removedScopes: [StorageScope] = []

    /// Creates a fake engine.
    public init(id: String = "fake", isAvailable: Bool = true) {
        descriptor = EngineDescriptor(id: id, displayName: id.capitalized, version: "test", isAvailable: isAvailable)
    }

    /// Makes a ``FakePage``.
    public func makePage(_ configuration: PageConfiguration, delegate: any WebPageDelegate) -> any WebPage {
        let page = FakePage(id: configuration.id, engineID: descriptor.id, delegate: delegate)
        pages[configuration.id] = page
        configurations.append(configuration)
        return page
    }

    /// Records the scope.
    public func removeWebsiteData(for scope: StorageScope) async { removedScopes.append(scope) }
    /// Cookies added per scope's ID (a profile ID for persistent scopes).
    public var addedCookies: [UUID: [WebCookie]] = [:]
    /// Cookies this engine holds per scope's ID, for ``cookies(forSite:in:)``.
    public var storedCookies: [UUID: [WebCookie]] = [:]
    /// Records the cookies.
    public func addCookies(_ cookies: [WebCookie], in scope: StorageScope) async -> Int {
        addedCookies[Self.key(scope), default: []] += cookies
        return cookies.count
    }
    static func key(_ scope: StorageScope) -> UUID {
        switch scope {
        case .persistent(let id), .ephemeral(let id): id
        }
    }
    /// The stored cookies of `site`.
    public func cookies(forSite site: String, in scope: StorageScope) async -> [WebCookie] {
        (storedCookies[Self.key(scope)] ?? []).filter { $0.belongs(to: site) }
    }
}

/// A page whose events and requests are driven by the test.
@MainActor
@Observable
public final class FakePage: WebPage {
    /// Page identity.
    public let id: UUID
    /// The engine that made it.
    public let engineID: String
    /// Settable state.
    public var state = PageState()
    /// Plain view.
    @ObservationIgnored public let view = PlatformView()
    /// URLs passed to ``load(_:)``.
    public private(set) var loads: [URL] = []
    /// Whether ``close()`` was called.
    public private(set) var isClosed = false
    /// Receives the simulated events and requests.
    @ObservationIgnored public weak var delegate: (any WebPageDelegate)?

    /// Creates a page.
    public init(id: UUID, engineID: String = "fake", delegate: (any WebPageDelegate)?) {
        self.id = id
        self.engineID = engineID
        self.delegate = delegate
    }

    /// Records the load and pretends it committed immediately.
    public func load(_ url: URL) {
        loads.append(url)
        simulateState { $0.url = url }
    }
    /// No-op.
    public func goBack() {}
    /// No-op.
    public func goForward() {}
    /// No-op.
    public func reload() {}
    /// Whether the page shows HTML full screen in a window of its own (like WebKit); settable.
    public var showsFullscreenInOwnWindow = false
    /// Counts the call (``exitFullscreenCount``).
    public func exitFullscreen() { exitFullscreenCount += 1 }
    /// How many times ``exitFullscreen()`` was called.
    public private(set) var exitFullscreenCount = 0
    /// Counts the call (``stopCount``).
    public func stop() { stopCount += 1 }
    /// How many times ``stop()`` was called.
    public private(set) var stopCount = 0
    /// Stores the zoom.
    public func setZoom(_ factor: Double) { state.zoom = factor }
    /// Stores the mute flag.
    public func setMuted(_ muted: Bool) { state.isMuted = muted }
    /// Always finds nothing.
    public func find(_ text: String, options: FindOptions) async -> FindResult { FindResult(matchFound: false) }
    /// No-op.
    public func clearFindResults() {}
    /// Records the URL in ``startedDownloads``.
    public func startDownload(_ url: URL) { startedDownloads.append(url) }
    /// Downloads started with ``startDownload(_:)``, in order.
    public private(set) var startedDownloads: [URL] = []
    /// Whether developer tools are allowed (``setDevToolsEnabled(_:)``).
    public private(set) var devToolsEnabled = false
    /// Times ``showDevTools()`` was called.
    public private(set) var devToolsShown = 0
    /// Records the setting.
    public func setDevToolsEnabled(_ enabled: Bool) { devToolsEnabled = enabled }
    /// Counts the call; succeeds only when enabled.
    public func showDevTools() -> Bool {
        guard devToolsEnabled else { return false }
        devToolsShown += 1
        return true
    }
    /// Records the ID in ``cancelledDownloads``.
    public func cancelDownload(_ id: UUID) { cancelledDownloads.append(id) }
    /// Downloads cancelled with ``cancelDownload(_:)``, in order.
    public private(set) var cancelledDownloads: [UUID] = []
    /// Marks the page closed.
    public func close() { isClosed = true }
    /// Scripts run with ``evaluate(_:)``, in order.
    public var evaluatedScripts: [String] = []
    /// What ``evaluate(_:)`` answers (by default `nil`).
    public var evaluateResult: (String) -> String? = { _ in nil }
    /// Records the script and answers with ``evaluateResult``.
    public func evaluate(_ script: String) async -> String? {
        evaluatedScripts.append(script)
        return evaluateResult(script)
    }

    /// Scripts run with ``evaluateAsUserGesture(_:)``, in order.
    public var gestureScripts: [String] = []
    /// Records the script and answers with ``evaluateResult``.
    public func evaluateAsUserGesture(_ script: String) async -> String? {
        gestureScripts.append(script)
        return evaluateResult(script)
    }

    /// Changes state and notifies the delegate.
    public func simulateState(_ change: (inout PageState) -> Void) {
        change(&state)
        delegate?.pageDidChangeState(self)
    }

    /// Emits an event to the delegate.
    public func simulate(_ event: PageEvent) {
        delegate?.page(self, didEmit: event)
    }

    /// Sends a request to the delegate.
    public func simulate(_ request: PageRequest) {
        delegate?.page(self, didRequest: request)
    }
}

/// Deterministic random numbers (SplitMix64) for fuzz and stress tests: a failure always reproduces from
/// the seed printed in its message.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Multiplies fuzz iteration counts: 1 on PRs, larger in the nightly run (`NERA_FUZZ_SCALE`).
    public static var scale: UInt64 { UInt64(ProcessInfo.processInfo.environment["NERA_FUZZ_SCALE"] ?? "") ?? 1 }

    /// Creates a generator for `seed`.
    public init(seed: UInt64) { state = seed }

    /// The next 64 random bits.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A random string mixing URL syntax, Unicode and control characters, up to `maxLength` characters.
    public mutating func fuzzString(maxLength: Int = 64) -> String {
        let pieces = [
            "http://", "https://", "file:///", "javascript:", "data:text/html,", "about:", "blob:", "mailto:", "zoommtg://", "view-source:",
            "user:pass@", "@", ":", "/", "//", "\\", "?", "#", "%", "%00", "%2F", "..", ".", " ", "\t", "\n", "\u{0}", "\u{202E}",
            "\u{200B}", "xn--", "例え", "ß", "🙂", "localhost", "127.0.0.1", "[::1]", "0x7f.1", ":80", ":65536", "a", "Z", "9", "-", "_",
            "~", "<script>", "'", "\"", "{query}", "&", "=", "+",
        ]
        var out = ""
        for _ in 0..<Int.random(in: 0...maxLength / 4, using: &self) { out += pieces.randomElement(using: &self)! }
        return out
    }

    /// `data` with a few random bytes flipped, removed or inserted.
    public mutating func mutate(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        for _ in 0..<Int.random(in: 1...8, using: &self) {
            guard !bytes.isEmpty else { break }
            let i = Int.random(in: 0..<bytes.count, using: &self)
            switch Int.random(in: 0..<3, using: &self) {
            case 0: bytes[i] = UInt8.random(in: 0...255, using: &self)
            case 1: bytes.remove(at: i)
            default: bytes.insert(Array("{}[]\",:0n".utf8).randomElement(using: &self)!, at: i)
            }
        }
        return Data(bytes)
    }
}
