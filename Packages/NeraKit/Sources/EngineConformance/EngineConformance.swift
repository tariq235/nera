// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
public import Foundation
public import SecurityPolicy

/// The shared conformance suite every `BrowserEngine` (EngineKit) must pass (ADR-0008).
///
/// Each engine's test target runs every case against a fresh engine instance. Cases that need a
/// capability the engine doesn't declare are reported as `unsupported`, never silently passed.
/// Results are written as JSON and rendered into `checklists/005-browser-engine.md`.
///
/// Cases use only `data:` URLs (no network) so they're deterministic and run anywhere.
public enum EngineConformance {
    /// Every case, in matrix order: the engine contract (C01–), then web security (S01–, ``SecurityConformance``).
    public static var cases: [ConformanceCase] { contractCases + featureCases + SecurityConformance.cases }

    /// The engine-contract cases.
    public static let contractCases: [ConformanceCase] = [
        ConformanceCase(id: "C01", title: "Load a typed URL; report title and committed URL", requires: []) { ctx in
            let (page, rec) = ctx.makePage()
            page.load(html("<title>Conformance</title><p>hi</p>"))
            try await ctx.wait("title") { page.state.title == "Conformance" }
            try ctx.expect(page.state.url?.scheme == "data", "committed URL is shown")
            try ctx.expect(rec.stateChanges > 0, "delegate receives state changes")
        },
        ConformanceCase(id: "C02", title: "Navigation lifecycle events in order: started → committed → finished", requires: []) { ctx in
            let (page, rec) = ctx.makePage()
            page.load(html("<title>Lifecycle</title>"))
            try await ctx.wait("finished") { rec.events.contains { if case .navigationFinished = $0 { true } else { false } } }
            let kinds = rec.events.compactMap { e -> String? in
                switch e {
                case .navigationStarted: "started"
                case .navigationCommitted: "committed"
                case .navigationFinished: "finished"
                default: nil
                }
            }
            try ctx.expect(kinds == ["started", "committed", "finished"], "got \(kinds)")
        },
        ConformanceCase(id: "C03", title: "Back/forward history", requires: []) { ctx in
            let (page, _) = ctx.makePage()
            page.load(html("<title>A</title>"))
            try await ctx.wait("A") { page.state.title == "A" && !page.state.isLoading }
            page.load(html("<title>B</title>"))
            try await ctx.wait("B") { page.state.title == "B" && page.state.canGoBack }
            page.goBack()
            try await ctx.wait("back to A") { page.state.title == "A" && page.state.canGoForward }
        },
        ConformanceCase(id: "C04", title: "Typed javascript: URL blocked before the engine loads anything", requires: []) { ctx in
            let (page, rec) = ctx.makePage()
            page.load(URL(string: "javascript:document.title='pwned'")!)
            try ctx.expect(rec.blocked == [.javascriptURL], "blocked event with reason, got \(rec.blocked)")
            try ctx.expect(page.state.url == nil, "nothing committed")
        },
        ConformanceCase(id: "C05", title: "Page script can't navigate to file: (blocked by the engine or the shared policy)", requires: [])
        { ctx in
            let (page, _) = ctx.makePage()
            page.load(html("<title>start</title><script>location.href='file:///etc/hosts'</script>"))
            try await ctx.wait("loaded") { page.state.title == "start" && !page.state.isLoading }
            try await Task.sleep(for: .milliseconds(500))
            try ctx.expect(page.state.url?.scheme == "data", "still on the original page, got \(String(describing: page.state.url))")
        },
        ConformanceCase(id: "C06", title: "alert() becomes a dialog request attributed to its origin", requires: [.javaScriptDialogs]) {
            ctx in
            let (page, rec) = ctx.makePage()
            rec.answer = { request in
                if case .dialog(let d) = request { d.decision.resolve(.ok(text: nil)) }
            }
            page.load(html("<script>alert('hello');document.title='after'</script>"))
            try await ctx.wait("title after alert") { page.state.title == "after" }
            guard case .dialog(let d)? = rec.requests.first else { throw ConformanceFailure("no dialog request") }
            try ctx.expect(d.kind == .alert(message: "hello"), "kind \(d.kind)")
            try ctx.expect(d.origin.isOpaque, "data: page has an opaque origin, got \(d.origin)")
        },
        ConformanceCase(id: "C07", title: "confirm() returns the user's answer", requires: [.javaScriptDialogs]) { ctx in
            let (page, rec) = ctx.makePage()
            rec.answer = { if case .dialog(let d) = $0 { d.decision.resolve(.ok(text: nil)) } }
            page.load(html("<script>document.title = confirm('sure?') ? 'yes' : 'no'</script>"))
            try await ctx.wait("yes") { page.state.title == "yes" }
        },
        ConformanceCase(id: "C08", title: "An unanswered dialog falls back to cancel (default-deny)", requires: [.javaScriptDialogs]) {
            ctx in
            let (page, rec) = ctx.makePage()
            rec.keepRequests = false  // drop every request without answering
            page.load(html("<script>document.title = confirm('sure?') ? 'yes' : 'no'</script>"))
            try await ctx.wait("no") { page.state.title == "no" }
        },
        ConformanceCase(id: "C09", title: "prompt() returns the entered text", requires: [.javaScriptDialogs]) { ctx in
            let (page, rec) = ctx.makePage()
            rec.answer = { if case .dialog(let d) = $0 { d.decision.resolve(.ok(text: "nera")) } }
            page.load(html("<script>document.title = 'got:' + prompt('name?', 'x')</script>"))
            try await ctx.wait("got:nera") { page.state.title == "got:nera" }
        },
        ConformanceCase(id: "C10", title: "Downloads ask for a destination and write the file", requires: [.downloads]) { ctx in
            let (page, rec) = ctx.makePage()
            let dir = FileManager.default.temporaryDirectory.appending(path: "nera-conformance-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appending(path: "file.txt")
            rec.answer = { if case .download(let d) = $0 { d.decision.resolve(.saveTo(dest)) } }
            page.startDownload(URL(string: "data:text/plain,conformance-download")!)
            try await ctx.wait("finished") { rec.downloadStates.contains(.finished(dest)) }
            try ctx.expect((try? String(contentsOf: dest, encoding: .utf8)) == "conformance-download", "file content")
        },
        ConformanceCase(id: "C11", title: "A download nobody answers is cancelled (default-deny)", requires: [.downloads]) { ctx in
            let (page, rec) = ctx.makePage()
            rec.keepRequests = false
            page.startDownload(URL(string: "data:text/plain,nope")!)
            try await ctx.wait("cancelled") { rec.downloadStates.contains(.cancelled) }
        },
        ConformanceCase(id: "C17", title: "A running download can be cancelled", requires: [.downloads]) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let (page, rec) = ctx.makePage()
            let dest = FileManager.default.temporaryDirectory.appending(path: "nera-cancel-\(UUID().uuidString).bin")
            var downloadID: UUID?
            rec.answer = {
                if case .download(let d) = $0 {
                    downloadID = d.id
                    d.decision.resolve(.saveTo(dest))
                }
            }
            page.startDownload(server.url("/slow-download"))
            try await ctx.wait("download running") {
                rec.downloadStates.contains { if case .progress(let received, _) = $0 { received > 0 } else { false } }
            }
            let id = try downloadID ?? { throw ConformanceFailure("no download request") }()
            page.cancelDownload(id)
            try await ctx.wait("cancelled") { rec.downloadStates.contains(.cancelled) }
            try ctx.expect(!rec.downloadStates.contains { if case .finished = $0 { true } else { false } }, "a cancelled download finished")
        },
        ConformanceCase(id: "C12", title: "Find in page", requires: [.findInPage]) { ctx in
            let (page, _) = ctx.makePage()
            page.load(html("<title>F</title><p>needle in a haystack</p>"))
            try await ctx.wait("loaded") { page.state.title == "F" && !page.state.isLoading }
            let hit = await page.find("needle", options: FindOptions())
            let miss = await page.find("zzzzzz", options: FindOptions())
            try ctx.expect(hit.matchFound && !miss.matchFound, "hit=\(hit) miss=\(miss)")
        },
        ConformanceCase(id: "C18", title: "Find again moves to the next match", requires: [.findInPage]) { ctx in
            let (page, _) = ctx.makePage()
            page.load(URL(string: "data:text/html,<title>FIND3</title><p>nera one</p><p>nera two</p><p>nera three</p>")!)
            try await ctx.wait("loaded") { page.state.title == "FIND3" }
            // The title can arrive before the text is laid out: retry the first search briefly.
            var first = await page.find("nera", options: FindOptions())
            for _ in 0..<20 where !first.matchFound {
                try await Task.sleep(for: .milliseconds(100))
                page.clearFindResults()
                first = await page.find("nera", options: FindOptions())
            }
            var actives: [Int] = first.activeMatch.map { [$0] } ?? []
            try ctx.expect(first.matchFound, "match not found")
            for _ in 0..<2 {
                let result = await page.find("nera", options: FindOptions())
                try ctx.expect(result.matchFound, "match not found")
                if let count = result.matchCount { try ctx.expect(count == 3, "expected 3 matches, got \(count)") }
                if let active = result.activeMatch { actives.append(active) }
            }
            if !actives.isEmpty { try ctx.expect(actives == [1, 2, 3], "find again didn't advance: \(actives)") }
            page.clearFindResults()
        },
        ConformanceCase(id: "C19", title: "The page's favicon is delivered as a PNG", requires: []) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let (page, _) = ctx.makePage()
            page.load(server.url("/icon-page"))  // plain HTTP: the WebKit icon fetch doesn't trust the test CA
            try await ctx.wait("favicon") { page.state.favicon != nil }
            let png = page.state.favicon ?? Data()
            try ctx.expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "favicon isn't a PNG")
        },
        ConformanceCase(id: "C13", title: "Page zoom is applied and reported", requires: [.pageZoom]) { ctx in
            let (page, _) = ctx.makePage()
            page.setZoom(1.5)
            try ctx.expect(page.state.zoom == 1.5, "zoom \(page.state.zoom)")
        },
        ConformanceCase(id: "C14", title: "Ephemeral and persistent scopes both work", requires: []) { ctx in
            let (persistent, _) = ctx.makePage(storage: .persistent(UUID()))
            let (ephemeral, _) = ctx.makePage(storage: .ephemeral(UUID()))
            persistent.load(html("<title>P</title>"))
            ephemeral.load(html("<title>E</title>"))
            try await ctx.wait("both loaded") { persistent.state.title == "P" && ephemeral.state.title == "E" }
        },
        ConformanceCase(id: "C15", title: "A closed page emits nothing more", requires: []) { ctx in
            let (page, rec) = ctx.makePage()
            page.load(html("<title>closing</title>"))
            page.close()
            try await Task.sleep(for: .milliseconds(300))
            try ctx.expect(rec.events.allSatisfy { if case .navigationFinished = $0 { false } else { true } }, "no finish after close")
        },
        ConformanceCase(
            id: "C16", title: "Page-initiated navigation is checked by the shared policy (credential URL blocked and reported)",
            requires: []
        ) { ctx in
            let (page, rec) = ctx.makePage()
            page.load(html("<title>start</title><script>location.href='https://user:pass@phish.invalid/'</script>"))
            try await ctx.wait("blocked") { rec.blocked.contains(.credentialsInURL) }
            try ctx.expect(page.state.url?.scheme == "data", "still on the original page")
        },
        ConformanceCase(id: "C20", title: "Nera's own scripts run in the page and return results", requires: []) { ctx in
            let (page, _) = ctx.makePage()
            page.load(html("<title>eval</title><p id=x>hello</p>"))
            try await ctx.wait("loaded") { page.state.title == "eval" }
            let text = await page.evaluate("document.getElementById('x').textContent")
            try ctx.expect(text == "hello", "string result \(text ?? "nil")")
            let json = await page.evaluate("({a: 1, b: [true]})")
            try ctx.expect(json == #"{"a":1,"b":[true]}"#, "object result \(json ?? "nil")")
            let failed = await page.evaluate("(() => { throw new Error('no') })()")
            try ctx.expect(failed == nil, "a throwing script returns nil")
        },
        ConformanceCase(id: "C21", title: "Video the engine can't play is detected (H.264 sample)", requires: []) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let (page, _) = ctx.makePage()
            let closeWindow = showOffscreen(page)
            defer { closeWindow() }
            page.load(server.url("/video"))
            try await ctx.wait("loaded") { page.state.title == "video" }
            // Either the engine plays it (metadata loads) or the probe reports it: never neither, never both.
            let outcome = try await mediaOutcome(page)
            try ctx.expect(outcome.playable != outcome.flagged, "playable=\(outcome.playable) flagged=\(outcome.flagged)")
            // A missing file (404) isn't a format problem.
            page.load(server.url("/video?src=/missing.mp4"))
            try await ctx.wait("loaded") { page.state.url?.query()?.contains("missing") == true && page.state.title == "video" }
            try ctx.expect(try await !flagsMissingVideo(page), "a 404 video was flagged as unplayable")
        },
    ]

    /// Runs one case against a fresh engine from `makeEngine`.
    @MainActor
    public static func run(_ testCase: ConformanceCase, makeEngine: @MainActor () -> any BrowserEngine) async -> ConformanceResult {
        let engine = makeEngine()
        guard engine.descriptor.isAvailable else {
            return ConformanceResult(caseID: testCase.id, title: testCase.title, outcome: .engineUnavailable)
        }
        let missing = testCase.requires.subtracting(engine.capabilities)
        guard missing.isEmpty else {
            return ConformanceResult(
                caseID: testCase.id, title: testCase.title,
                outcome: .unsupported(missing.map(\.rawValue).sorted()))
        }
        let context = ConformanceContext(engine: engine)
        do {
            try await testCase.body(context)
            context.closeAll()
            return ConformanceResult(caseID: testCase.id, title: testCase.title, outcome: .passed)
        } catch {
            context.closeAll()
            return ConformanceResult(caseID: testCase.id, title: testCase.title, outcome: .failed("\(error)"))
        }
    }

    /// Runs every case and returns a report for the parity matrix.
    @MainActor
    public static func report(makeEngine: @MainActor () -> any BrowserEngine) async -> ConformanceReport {
        let descriptor = makeEngine().descriptor
        var results: [ConformanceResult] = []
        for testCase in cases { results.append(await run(testCase, makeEngine: makeEngine)) }
        return ConformanceReport(
            engineID: descriptor.id, engineName: descriptor.displayName,
            engineVersion: descriptor.version, results: results)
    }

    /// A `data:` URL for an HTML snippet.
    public static func html(_ body: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "data:text/html;charset=utf-8,\(encoded)")!
    }
}

/// One conformance case.
public struct ConformanceCase: Sendable, CustomStringConvertible {
    /// Stable ID used in the matrix, e.g. `C06`.
    public let id: String
    /// What it proves.
    public let title: String
    /// Capabilities the case needs; engines without them report `unsupported`.
    public let requires: EngineCapabilities
    /// The test body.
    public let body: @MainActor @Sendable (ConformanceContext) async throws -> Void

    /// Creates a case.
    public init(
        id: String, title: String, requires: EngineCapabilities,
        body: @escaping @MainActor @Sendable (ConformanceContext) async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.requires = requires
        self.body = body
    }

    /// `C06 alert() becomes …` (used as the test-argument label).
    public var description: String { "\(id) \(title)" }
}

/// Outcome of one case on one engine.
public struct ConformanceResult: Codable, Equatable, Sendable {
    /// The case ID.
    public var caseID: String
    /// The case title.
    public var title: String
    /// What happened.
    public var outcome: Outcome

    /// Possible outcomes.
    public enum Outcome: Codable, Equatable, Sendable {
        /// The engine behaved as the contract requires.
        case passed
        /// The engine broke the contract.
        case failed(String)
        /// The engine doesn't declare these capabilities.
        case unsupported([String])
        /// The engine isn't available on this build.
        case engineUnavailable
    }
}

/// All results for one engine.
public struct ConformanceReport: Codable, Equatable, Sendable {
    /// Engine ID, e.g. `webkit`.
    public var engineID: String
    /// Engine display name.
    public var engineName: String
    /// Engine version.
    public var engineVersion: String
    /// One result per case.
    public var results: [ConformanceResult]
}

/// A contract violation.
public struct ConformanceFailure: Error, CustomStringConvertible {
    /// What went wrong.
    public let description: String
    /// Creates a failure.
    public init(_ description: String) { self.description = description }
}

/// Helpers available to a case body.
@MainActor
public final class ConformanceContext {
    /// The engine under test.
    public let engine: any BrowserEngine
    private var recorders: [Recorder] = []
    private var pages: [any WebPage] = []

    init(engine: any BrowserEngine) { self.engine = engine }

    /// Creates a page with a recording delegate.
    public func makePage(storage: StorageScope = .ephemeral(UUID()), policy: NavigationPolicy = NavigationPolicy()) -> (
        any WebPage, Recorder
    ) {
        let recorder = Recorder()
        let page = engine.makePage(PageConfiguration(id: UUID(), storage: storage, policy: policy), delegate: recorder)
        recorders.append(recorder)
        pages.append(page)
        return (page, recorder)
    }

    /// Polls `condition` every 20 ms until it's true, or throws after `timeout`.
    public func wait(_ what: String, timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw ConformanceFailure("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Throws `message` unless `condition` holds.
    public func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ConformanceFailure(message()) }
    }

    func closeAll() {
        for page in pages { page.close() }
    }
}

/// Records everything a page reports. Optionally answers or drops requests.
@MainActor
public final class Recorder: WebPageDelegate {
    /// Events, in order.
    public private(set) var events: [PageEvent] = []
    /// Requests that were kept, in order.
    public private(set) var requests: [PageRequest] = []
    /// Number of state-change callbacks.
    public private(set) var stateChanges = 0
    /// Answers each request as it arrives (if set).
    public var answer: ((PageRequest) -> Void)?
    /// When `false`, requests are dropped unanswered (to test default-deny fallbacks).
    public var keepRequests = true

    /// Creates an empty recorder (adapter unit tests use one directly, outside the suite).
    public init() {}

    /// Reasons of `navigationBlocked` events.
    public var blocked: [NavigationPolicy.Reason] {
        events.compactMap { if case .navigationBlocked(_, let reason) = $0 { reason } else { nil } }
    }

    /// States of download events.
    public var downloadStates: [DownloadEvent.State] {
        events.compactMap { if case .download(let d) = $0 { d.state } else { nil } }
    }

    /// Counts the change.
    public func pageDidChangeState(_ page: any WebPage) { stateChanges += 1 }
    /// Records the event.
    public func page(_ page: any WebPage, didEmit event: PageEvent) { events.append(event) }
    /// Records, answers or drops the request.
    public func page(_ page: any WebPage, didRequest request: PageRequest) {
        answer?(request)
        if keepRequests { requests.append(request) }
    }
}

/// Fixed profile IDs the conformance cases share with the app's self-test setup.
public enum EngineConformanceProfiles {
    /// The profile the self-test loads the fixture extension into (X-cases).
    public static let extensions = UUID(uuidString: "00000000-0000-0000-0000-00000000E701") ?? UUID()
    /// The fixture extension's ID (Tests/Fixtures/extensions/nera-test-blocker; fixed by its manifest `key`).
    public static let fixtureExtensionID = "kegcdocifkpnanhhigbefpoghfinenhp"
}

/// A scripted authenticator for the P-cases: records requests; rp name "Fail" is refused.
@MainActor
public final class TestWebAuthenticator: WebAuthenticator {
    /// The instance the self-test gives the Chromium engine.
    public static let shared = TestWebAuthenticator()
    /// Requests seen, in order.
    public var requests: [WebAuthnRequest] = []
    /// Always available (the P-cases exercise the full path).
    public let isAvailable = true

    /// Creates a fresh test authenticator.
    public init() {}

    /// Answers with a fixed credential (id 0x010203).
    public func perform(_ request: WebAuthnRequest) async -> WebAuthnResult {
        requests.append(request)
        if request.optionsJSON.contains("\"Fail\"") { return .unavailable }
        switch request.kind {
        case .available: return .success("true")
        case .create:
            return .success(#"{"id":"AQID","clientDataJSON":"e30","attestationObject":"AQIDBAU","authenticatorAttachment":"platform"}"#)
        case .get:
            return .success(#"{"id":"AQID","clientDataJSON":"e30","authenticatorData":"AQID","signature":"AQID","userHandle":"dQ"}"#)
        }
    }
}

extension EngineConformance {
    /// Extension (X) and passkey (P) cases.
    public static let featureCases: [ConformanceCase] = [
        ConformanceCase(
            id: "X01", title: "Installed extensions run in profile pages (content blocking + content scripts)", requires: [.extensions]
        ) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let (page, _) = ctx.makePage(storage: .persistent(EngineConformanceProfiles.extensions))
            let adsBefore = server.requests("/ad-probe").count
            page.load(server.url("/ext-page"))
            try await ctx.wait("probes") { page.state.title.hasPrefix("EXT ") && page.state.title != "EXT WAIT" }
            try ctx.expect(page.state.title.hasPrefix("EXT ON"), "content script didn't run: \(page.state.title)")
            try ctx.expect(page.state.title == "EXT ON ok err", "expected the ad request blocked: \(page.state.title)")
            try ctx.expect(server.requests("/ad-probe").count == adsBefore, "the blocked request reached the server")
        },
        ConformanceCase(id: "X02", title: "Nera opens an installed extension's popup page", requires: [.extensions]) { ctx in
            var policy = NavigationPolicy()
            policy.allowsExtensionPages = true
            let (popup, _) = ctx.makePage(storage: .persistent(EngineConformanceProfiles.extensions), policy: policy)
            popup.load(URL(string: "chrome-extension://\(EngineConformanceProfiles.fixtureExtensionID)/popup.html")!)
            try await ctx.wait("popup") { popup.state.title == "Nera Test Blocker" }
            let (web, _) = ctx.makePage(storage: .persistent(EngineConformanceProfiles.extensions))
            web.load(URL(string: "chrome-extension://\(EngineConformanceProfiles.fixtureExtensionID)/popup.html")!)
            try await Task.sleep(for: .milliseconds(800))
            try ctx.expect(web.state.title != "Nera Test Blocker", "an ordinary page reached an extension page")
        },
        ConformanceCase(
            id: "P01", title: "Passkeys: a page's WebAuthn reaches Nera's authenticator with the frame's real origin",
            requires: [.webAuthnBridge]
        ) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let auth = TestWebAuthenticator.shared
            auth.requests.removeAll()
            let (page, _) = ctx.makePage(storage: .persistent(UUID()))
            let port = server.url("/").port ?? 0
            page.load(URL(string: "http://localhost:\(port)/webauthn?rp=Nera")!)
            try await ctx.wait("webauthn", timeout: .seconds(15)) { page.state.title.hasPrefix("WA ") && page.state.title != "WA WAIT" }
            try ctx.expect(page.state.title == "WA OK public-key AQID 5 3 true", "unexpected credential: \(page.state.title)")
            try ctx.expect(auth.requests.map(\.kind) == [.available, .create, .get], "requests: \(auth.requests.map(\.kind))")
            try ctx.expect(
                auth.requests.allSatisfy { $0.origin.description == "http://localhost:\(port)" }, "origin not taken from the frame")
        },
        ConformanceCase(
            id: "P02", title: "Passkeys: a refused request rejects with NotAllowedError (never hangs)", requires: [.webAuthnBridge]
        ) { ctx in
            guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
            let (page, _) = ctx.makePage(storage: .persistent(UUID()))
            page.load(URL(string: "http://localhost:\(server.url("/").port ?? 0)/webauthn?rp=Fail")!)
            try await ctx.wait("webauthn", timeout: .seconds(10)) { page.state.title.hasPrefix("WA ") && page.state.title != "WA WAIT" }
            try ctx.expect(page.state.title.hasPrefix("WA ERR NotAllowedError"), "unexpected: \(page.state.title)")
        },
    ]
}
