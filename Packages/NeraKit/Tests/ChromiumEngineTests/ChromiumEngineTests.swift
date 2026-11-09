// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineConformance
import EngineKit
import Foundation
import SecurityPolicy
import Testing

@testable import ChromiumEngine

/// Without a CEF backend (iOS, plain `swift test`), the adapter still compiles against the full contract
/// (ENG-020) and honestly reports itself unavailable. Real-Chromium conformance (and the parity matrix's
/// Chromium column) comes from the macOS app's engine self-test, where CEF exists (ADR-0010).
@MainActor
@Suite("Chromium conformance (no backend)")
struct ChromiumConformanceTests {
    @Test(arguments: EngineConformance.cases)
    func conformance(_ testCase: ConformanceCase) async {
        let result = await EngineConformance.run(testCase) { ChromiumEngine() }
        switch result.outcome {
        case .passed, .unsupported: break
        case .engineUnavailable:
            #expect(!ChromiumEngine().descriptor.isAvailable, "only acceptable while no backend is bundled")
        case .failed(let why): Issue.record("\(testCase.id) failed: \(why)")
        }
    }

    @Test func placeholderIsHonestAboutItsState() {
        let engine = ChromiumEngine()
        #expect(engine.descriptor.id == "chromium")
        #expect(!engine.descriptor.isAvailable)
        #expect(engine.capabilities.isEmpty)
    }

    @Test func aBackendThatFailedToStartLeavesTheEngineUnavailable() {
        let engine = ChromiumEngine(backend: FakeBackend(running: false))
        #expect(!engine.descriptor.isAvailable)
        #expect(engine.capabilities.isEmpty)
    }

    @Test func availabilityFollowsTheBackendAtUseTime() {
        let backend = FakeBackend(running: false)
        let engine = ChromiumEngine(backend: backend)
        #expect(!engine.descriptor.isAvailable)
        backend.isRunning = true  // the app starts CEF after building its engine list
        #expect(engine.descriptor.isAvailable)
    }
}

/// The adapter's own logic, against a fake backend: what Nera asks Chromium to do, and how Chromium's
/// callbacks become contract events and default-deny requests.
@MainActor
@Suite("Chromium adapter")
struct ChromiumAdapterTests {
    let backend = FakeBackend()
    let recorder = Recorder()

    /// The page is kept alive by the backend fake for the test's duration (in Nera, the tab owns it);
    /// the handle holds its events weakly, like the real CEF bridge.
    func makePage(_ storage: StorageScope = .ephemeral(UUID())) -> (any WebPage, FakeHandle) {
        let page = ChromiumEngine(backend: backend).makePage(
            PageConfiguration(id: UUID(), storage: storage, policy: NavigationPolicy()), delegate: recorder)
        backend.keepAlive.append(page)
        return (page, backend.handles.last!)
    }

    @Test func availableEngineDeclaresWhatItImplements() {
        let engine = ChromiumEngine(backend: backend)
        #expect(engine.descriptor.isAvailable)
        #expect(engine.descriptor.version == "CEF test")
        #expect(
            engine.capabilities == [
                .javaScriptDialogs, .downloads, .findInPage, .pageZoom, .mediaPermissionRequests, .extensions, .webAuthnBridge,
            ])
    }

    @Test func typedJavascriptURLNeverReachesChromium() {
        let (page, handle) = makePage()
        page.load(URL(string: "javascript:alert(1)")!)
        #expect(handle.loads.isEmpty)
        #expect(recorder.blocked == [.javascriptURL])
    }

    @Test func typedHTTPIsUpgradedBeforeChromiumSeesIt() {
        let (page, handle) = makePage()
        page.load(URL(string: "http://example.com/a")!)
        #expect(handle.loads == ["https://example.com/a"])
    }

    @Test func pageInitiatedNavigationsGoThroughTheSharedPolicy() {
        let (_, handle) = makePage()
        #expect(handle.events?.shouldNavigate(to: "https://example.com/", mainFrame: true, trigger: .linkClick) == true)
        #expect(handle.events?.shouldNavigate(to: "file:///etc/hosts", mainFrame: true, trigger: .script) == false)
        #expect(handle.events?.shouldNavigate(to: "https://u:p@phish.invalid/", mainFrame: true, trigger: .script) == false)
        #expect(handle.events?.shouldNavigate(to: "data:text/html,x", mainFrame: true, trigger: .script) == false)
        #expect(handle.events?.shouldNavigate(to: "data:text/html,x", mainFrame: true, trigger: .userTyped) == true)
        #expect(recorder.blocked == [.fileURLFromWeb, .credentialsInURL, .dataURLTopLevel])
    }

    @Test func lifecycleEventsAndCommittedURL() {
        let (page, handle) = makePage()
        _ = handle.events?.shouldNavigate(to: "https://example.com/", mainFrame: true, trigger: .userTyped)
        #expect(page.state.url == nil, "a pending URL is never shown (SR-016)")
        handle.events?.didCommit(url: "https://example.com/")
        handle.events?.didFinish(url: "https://example.com/", httpStatus: 200)
        #expect(page.state.url?.absoluteString == "https://example.com/")
        #expect(recorder.kinds == ["started", "committed", "finished"])
    }

    @Test func rawURLsFromChromiumStillBecomeTheCommittedURL() {
        let (page, handle) = makePage()
        handle.events?.didCommit(url: "data:text/html,<title>Smoke Page</title><h1>ok</h1>")
        #expect(page.state.url?.scheme == "data", "pin/restore need the tab's URL")
        #expect(ChromiumPage.parseURL("https://example.com/a%20b?q=1#f")?.absoluteString == "https://example.com/a%20b?q=1#f")
    }

    @Test func abortedLoadsAreNotFailures() {
        let (_, handle) = makePage()
        handle.events?.didFail(url: "https://example.com/", code: -3, description: "ERR_ABORTED")
        handle.events?.didFail(url: "https://example.com/", code: -105, description: "ERR_NAME_NOT_RESOLVED")
        #expect(recorder.kinds == ["failed"])
    }

    @Test func titleThatIsJustTheURLShowsAsEmpty() {
        let (page, handle) = makePage()
        handle.events?.didCommit(url: "https://example.com/")
        handle.events?.titleChanged("https://example.com/")
        #expect(page.state.title.isEmpty)
        handle.events?.titleChanged("Example")
        #expect(page.state.title == "Example")
    }

    @Test func dialogsCarryTheirOriginAndAnUnansweredOneIsCancelled() {
        let (_, handle) = makePage()
        var replies: [(Bool, String?)] = []
        recorder.keepRequests = false  // drop the request unanswered
        handle.events?.dialog(kind: .confirm, originURL: "https://site.example/", message: "Sure?", defaultText: "") {
            replies.append(($0, $1))
        }
        #expect(replies.count == 1 && replies[0].0 == false, "default-deny: cancel")
    }

    @Test func answeredPromptReturnsTheText() {
        let (_, handle) = makePage()
        var replies: [(Bool, String?)] = []
        recorder.answer = { if case .dialog(let d) = $0 { d.decision.resolve(.ok(text: "nera")) } }
        handle.events?.dialog(kind: .prompt, originURL: "https://site.example/", message: "Name?", defaultText: "x") {
            replies.append(($0, $1))
        }
        guard case .dialog(let d)? = recorder.requests.first else {
            Issue.record("no dialog request")
            return
        }
        #expect(d.origin.description == "https://site.example")
        #expect(d.kind == .prompt(message: "Name?", defaultText: "x"))
        #expect(replies.count == 1 && replies[0].0 && replies[0].1 == "nera")
    }

    @Test func permissionRequestsBecomeDefaultDenyRequests() {
        let (_, handle) = makePage()
        var replies: [Bool] = []
        recorder.keepRequests = false  // dropped unanswered
        handle.events?.permissionRequested(origin: "https://meet.example/", kinds: [.camera, .microphone]) { replies.append($0) }
        #expect(replies == [false], "default-deny")
        recorder.keepRequests = true
        recorder.answer = { if case .permission(let p) = $0 { p.decision.resolve(.grant) } }
        handle.events?.permissionRequested(origin: "https://meet.example/", kinds: [.location]) { replies.append($0) }
        guard case .permission(let p)? = recorder.requests.last else {
            Issue.record("no permission request")
            return
        }
        #expect(p.kinds == [.location] && p.origin.description == "https://meet.example")
        #expect(replies == [false, true])
    }

    @Test func unansweredDownloadIsCancelledAndReported() {
        let (_, handle) = makePage()
        var paths: [String?] = []
        recorder.keepRequests = false
        handle.events?.downloadRequested(
            ChromiumDownloadInfo(id: 7, url: "https://x.example/f.zip", suggestedName: "f.zip", mimeType: "", totalBytes: 0)
        ) { paths.append($0) }
        #expect(paths == [nil])
        #expect(recorder.downloadStates == [.cancelled])
    }

    @Test func acceptedDownloadReportsProgressAndCompletion() {
        let (_, handle) = makePage()
        let dest = URL(fileURLWithPath: "/tmp/nera-test/f.zip")
        var paths: [String?] = []
        recorder.answer = { if case .download(let d) = $0 { d.decision.resolve(.saveTo(dest)) } }
        handle.events?.downloadRequested(
            ChromiumDownloadInfo(id: 9, url: "https://x.example/f.zip", suggestedName: "f.zip", mimeType: "application/zip", totalBytes: 10)
        ) { paths.append($0) }
        handle.events?.downloadUpdated(ChromiumDownloadProgress(id: 9, received: 5, total: 10))
        handle.events?.downloadUpdated(ChromiumDownloadProgress(id: 9, received: 10, total: 10, isComplete: true, path: dest.path))
        handle.events?.downloadUpdated(ChromiumDownloadProgress(id: 9, received: 10, total: 10, isComplete: true, path: dest.path))
        #expect(paths == [dest.path])
        #expect(recorder.downloadStates == [.progress(received: 5, total: 10), .finished(dest)], "nothing after completion")
    }

    @Test func findResolvesOnTheFinalResult() async {
        let (page, handle) = makePage()
        handle.onFind = { [weak handle] in
            handle?.events?.findMatches(2, active: 1, isFinal: false)
            handle?.events?.findMatches(3, active: 1, isFinal: true)
        }
        #expect(await page.find("needle", options: FindOptions()).matchFound)
        #expect(handle.finds == ["needle forward caseInsensitive"])
    }

    @Test func zoomAndMuteAreAppliedAndReported() {
        let (page, handle) = makePage()
        page.setZoom(1.5)
        page.setMuted(true)
        #expect(handle.zoom == 1.5 && handle.muted)
        #expect(page.state.zoom == 1.5 && page.state.isMuted)
    }

    @Test func rendererTerminationIsMapped() {
        let (_, handle) = makePage()
        handle.events?.processTerminated(.crashed)
        handle.events?.processTerminated(.outOfMemory)
        handle.events?.processTerminated(.killed)
        let expected: [PageEvent] = [.processTerminated(.crashed), .processTerminated(.memoryPressure), .processTerminated(.unknown)]
        #expect(recorder.events == expected)
    }

    @Test func aClosedPageSendsNothingAndRefusesEverything() async {
        let (page, handle) = makePage()
        page.close()
        #expect(handle.closed)
        handle.events?.didCommit(url: "https://example.com/")
        #expect(handle.events?.shouldNavigate(to: "https://example.com/", mainFrame: true, trigger: .userTyped) == false)
        var replies: [Bool] = []
        handle.events?.dialog(kind: .alert, originURL: "", message: "x", defaultText: "") { ok, _ in replies.append(ok) }
        page.load(URL(string: "https://example.com/")!)
        #expect(recorder.events.isEmpty && recorder.requests.isEmpty)
        #expect(replies == [false])
        #expect(handle.loads.isEmpty)
        #expect(await page.find("x", options: FindOptions()).matchFound == false)
    }

    @Test func storageScopesMapToSeparateRequestContexts() async {
        let profile = UUID()
        let session = UUID()
        _ = makePage(.persistent(profile))
        _ = makePage(.ephemeral(session))
        #expect(backend.contexts == ["\(profile.uuidString) persistent", "ephemeral-\(session.uuidString) memory"])
        await ChromiumEngine(backend: backend).removeWebsiteData(for: .persistent(profile))
        #expect(backend.removed == ["\(profile.uuidString) persistent"])
    }

    @Test func triggersMapOneToOne() {
        #expect(ChromiumPage.policyTrigger(.userTyped) == .userTyped)
        #expect(ChromiumPage.policyTrigger(.linkClick) == .linkClick)
        #expect(ChromiumPage.policyTrigger(.script) == .script)
        #expect(ChromiumPage.policyTrigger(.redirect) == .redirect)
    }
}

// MARK: - Fakes

@MainActor
final class FakeBackend: ChromiumBackend {
    var isRunning: Bool
    let version = "CEF test"
    private(set) var handles: [FakeHandle] = []
    /// The `passkeys` flag of the last page made.
    var lastPasskeys = false
    private(set) var contexts: [String] = []
    private(set) var removed: [String] = []
    var keepAlive: [any WebPage] = []

    init(running: Bool = true) { isRunning = running }

    func makePage(storageKey: String, persistent: Bool, passkeys: Bool, events: any ChromiumPageEvents) -> any ChromiumPageHandle {
        lastPasskeys = passkeys
        contexts.append("\(storageKey) \(persistent ? "persistent" : "memory")")
        let handle = FakeHandle(events: events)
        handles.append(handle)
        return handle
    }

    func removeData(storageKey: String, persistent: Bool) async {
        removed.append("\(storageKey) \(persistent ? "persistent" : "memory")")
    }

    var cookies: [String: [WebCookie]] = [:]
    func setCookies(_ cookies: [WebCookie], storageKey: String, persistent: Bool) async -> Int {
        self.cookies[storageKey, default: []] += cookies
        return cookies.count
    }
    func cookies(forSite site: String, storageKey: String, persistent: Bool) async -> [WebCookie] {
        (cookies[storageKey] ?? []).filter { $0.belongs(to: site) }
    }
}

@MainActor
final class FakeHandle: ChromiumPageHandle {
    weak var events: (any ChromiumPageEvents)?
    let view = PlatformView()
    private(set) var loads: [String] = []
    private(set) var finds: [String] = []
    private(set) var zoom = 1.0
    private(set) var muted = false
    private(set) var closed = false
    var onFind: () -> Void = {}

    init(events: any ChromiumPageEvents) { self.events = events }

    func load(_ url: String) { loads.append(url) }
    func goBack() {}
    func goForward() {}
    func reload() {}
    func stop() {}
    var exitedFullscreen = false
    func exitFullscreen() { exitedFullscreen = true }
    func setZoomFactor(_ factor: Double) { zoom = factor }
    func setMuted(_ muted: Bool) { self.muted = muted }
    func find(_ text: String, forward: Bool, matchCase: Bool, findNext: Bool) {
        finds.append("\(text) \(forward ? "forward" : "backward") \(matchCase ? "caseSensitive" : "caseInsensitive")")
        onFind()
    }
    func stopFinding() {}
    func startDownload(_ url: String) {}
    var cancelledDownloads: [UInt32] = []
    func cancelDownload(_ id: UInt32) { cancelledDownloads.append(id) }
    var devToolsEnabled = false
    var devToolsShown = 0
    func setDevToolsEnabled(_ enabled: Bool) { devToolsEnabled = enabled }
    func showDevTools() { devToolsShown += 1 }
    func close() { closed = true }
    var scripts: [String] = []
    func evaluate(_ script: String) async -> String? {
        scripts.append(script)
        return "ok"
    }
}

extension Recorder {
    var kinds: [String] {
        events.compactMap {
            switch $0 {
            case .navigationStarted: "started"
            case .navigationCommitted: "committed"
            case .navigationFinished: "finished"
            case .navigationFailed: "failed"
            default: nil
            }
        }
    }
}

/// FEAT-027: the WebAuthn bridge's own checks, before any authenticator is asked.
@MainActor
@Suite("Chromium WebAuthn bridge")
struct ChromiumWebAuthnBridgeTests {
    let backend = FakeBackend()
    let recorder = Recorder()

    func page(_ authenticator: (any WebAuthenticator)?) -> FakeHandle {
        let page = ChromiumEngine(backend: backend, webAuthenticator: authenticator).makePage(
            PageConfiguration(id: UUID(), storage: .ephemeral(UUID()), policy: NavigationPolicy()), delegate: recorder)
        backend.keepAlive.append(page)
        return backend.handles.last!
    }

    func ask(_ handle: FakeHandle, _ kind: String, frame: String, top: String) async -> (Bool, String) {
        await withCheckedContinuation { done in
            handle.events?.webAuthnRequested(kind: kind, json: "{}", frameURL: frame, topURL: top) { done.resume(returning: ($0, $1)) }
        }
    }

    @Test func refusalsHappenBeforeTheAuthenticator() async {
        let auth = TestWebAuthenticator()
        let h = page(auth)
        let insecure = await ask(h, "create", frame: "http://site.example/", top: "http://site.example/")
        #expect(!insecure.0 && insecure.1.hasPrefix("SecurityError|"))
        let file = await ask(h, "get", frame: "file:///tmp/x.html", top: "file:///tmp/x.html")
        #expect(!file.0 && file.1.hasPrefix("SecurityError|"))
        let framed = await ask(h, "get", frame: "https://widget.example/", top: "https://shop.example/")
        #expect(!framed.0 && framed.1.hasPrefix("NotAllowedError|"), "cross-origin iframes are refused")
        let unknown = await ask(h, "delete", frame: "https://a.example/", top: "https://a.example/")
        #expect(!unknown.0)
        #expect(auth.requests.isEmpty, "none of these reached the authenticator")
        #expect(backend.lastPasskeys == true, "PublicKeyCredential exposed when an authenticator is available")
    }

    @Test func requestsCarryTheFramesOriginAndAnswersComeBack() async {
        let auth = TestWebAuthenticator()
        let h = page(auth)
        let answer = await ask(h, "create", frame: "https://login.example/path?x", top: "https://login.example/")
        #expect(answer.0 && answer.1.contains("attestationObject"))
        #expect(auth.requests.first?.origin.description == "https://login.example")
        let local = await ask(h, "available", frame: "http://localhost:3000/", top: "http://localhost:3000/")
        #expect(local == (true, "true"), "loopback counts as secure for development")
    }

    @Test func withoutAnAuthenticatorPagesFailFast() async {
        let h = page(nil)
        let get = await ask(h, "get", frame: "https://a.example/", top: "https://a.example/")
        #expect(!get.0 && get.1.hasPrefix("NotAllowedError|"))
        #expect(await ask(h, "available", frame: "https://a.example/", top: "https://a.example/") == (true, "false"))
        #expect(backend.lastPasskeys == false, "no PublicKeyCredential without an authenticator")
    }
}
