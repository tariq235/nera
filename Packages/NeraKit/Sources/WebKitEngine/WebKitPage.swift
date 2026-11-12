// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import Observation
import SecurityPolicy
import WebKit

/// A ``WebPage`` backed by `WKWebView`. Internal: callers only ever see `any WebPage`.
@MainActor
@Observable
final class WebKitPage: NSObject, WebPage {
    let id: UUID
    private(set) var state = PageState()

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let storage: StorageScope
    @ObservationIgnored private let policy: NavigationPolicy
    @ObservationIgnored private weak var delegate: (any WebPageDelegate)?
    @ObservationIgnored private weak var engine: WebKitEngine?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// URL we are loading because the user asked for it; it gets `.userTyped` trust once.
    @ObservationIgnored private var pendingUserURL: URL?
    /// A main-frame navigation is between "started" and "committed".
    @ObservationIgnored private var provisionalInFlight = false
    @ObservationIgnored private(set) var isClosed = false
    @ObservationIgnored private var downloadIDs: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var downloadDestinations: [UUID: URL] = [:]
    @ObservationIgnored private var downloadObservations: [UUID: NSKeyValueObservation] = [:]
    @ObservationIgnored private var downloadObjects: [UUID: WKDownload] = [:]
    @ObservationIgnored private var cancelledDownloads: Set<UUID> = []
    /// Frames playing sound, and each frame that reported (to mute it): WebKitPage+Sound.swift.
    @ObservationIgnored var mediaFrames = MediaWatch.Frames()
    @ObservationIgnored var mediaFrameInfos: [String: WKFrameInfo] = [:]

    var view: PlatformView { webView }

    init(
        id: UUID, storage: StorageScope, configuration: WKWebViewConfiguration, policy: NavigationPolicy,
        delegate: any WebPageDelegate, engine: WebKitEngine
    ) {
        self.id = id
        self.storage = storage
        self.policy = policy
        self.delegate = delegate
        self.engine = engine
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false  // Nera draws its own swipe (SwipeNavigation), the same on every engine
        #if os(macOS)
            webView.setAccessibilityIdentifier("web.content")
        #else
            webView.accessibilityIdentifier = "web.content"
        #endif
        observe()
    }

    // MARK: WebPage

    func load(_ url: URL) {
        guard !isClosed else { return }
        switch policy.decide(url, trigger: .userTyped) {
        case .allow: start(url)
        case .upgrade(let upgraded):
            emit(.upgradedToHTTPS(from: url))
            start(upgraded)
        case .block(let reason): emit(.navigationBlocked(url, reason))
        case .askToOpenExternally(let ext): requestExternalApp(ext)
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadIgnoringCache() { webView.reloadFromOrigin() }
    func stop() { webView.stopLoading() }

    func setZoom(_ factor: Double) {
        webView.pageZoom = CGFloat(factor)
        update { $0.zoom = factor }
    }

    func find(_ text: String, options: FindOptions) async -> FindResult {
        let config = WKFindConfiguration()
        config.backwards = options.backwards
        config.caseSensitive = options.caseSensitive
        config.wraps = options.wraps
        let result = try? await webView.find(text, configuration: config)
        return FindResult(matchFound: result?.matchFound ?? false)
    }

    func clearFindResults() {
        // Runs in WebKit's isolated client world: invisible to page scripts.
        webView.evaluateJavaScript("window.getSelection()?.removeAllRanges()", in: nil, in: .defaultClient) { _ in }
    }

    func startDownload(_ url: URL) {
        guard !isClosed else { return }
        if case .block(let reason) = policy.decide(url, trigger: .userTyped) {
            emit(.navigationBlocked(url, reason))
            return
        }
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            self?.adopt(download)
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        silenceMedia()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.mediaHandlerName, contentWorld: .defaultClient)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        for observation in observations { observation.invalidate() }
        observations = []
        for observation in downloadObservations.values { observation.invalidate() }
        webView.removeFromSuperview()
        engine?.releaseStore(for: storage)
    }

    // MARK: Internals

    private func start(_ url: URL) {
        pendingUserURL = url
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func update(_ mutate: (inout PageState) -> Void) {
        var next = state
        mutate(&next)
        guard next != state else { return }
        state = next
        delegate?.pageDidChangeState(self)
    }

    func emit(_ event: PageEvent) {
        guard !isClosed else { return }
        delegate?.page(self, didEmit: event)
    }

    /// Sends a request and suspends until it is answered (or released, which applies the fallback).
    private func ask<Answer: Sendable>(fallback: Answer, _ make: (Decision<Answer>) -> PageRequest) async -> Answer {
        await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            let decision = Decision(fallback: fallback) { continuation.resume(returning: $0) }
            if !isClosed, let delegate {
                delegate.page(self, didRequest: make(decision))
            }
            // If nobody kept the request, `decision` is released here and resolves to `fallback`.
        }
    }

    private func requestExternalApp(_ url: URL) {
        let request = ExternalAppRequest(
            url: url, origin: SecurityOrigin(url: webView.url),
            decision: Decision(fallback: .block) { _ in })
        delegate?.page(self, didRequest: .externalApp(request))
    }

    /// Reads the page's icon links in Nera's isolated content world, then fetches the best icon.
    private func loadFavicon() {
        guard let pageURL = webView.url, FaviconLoader.isWeb(pageURL), state.favicon == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let raw = try? await webView.evaluateJavaScript(FaviconLoader.script, in: nil, contentWorld: .defaultClient)
            let links = (raw as? [[Any]] ?? []).map { $0.map { "\($0)" } }
            let png = await FaviconLoader.load(FaviconLoader.candidates(links: links, pageURL: pageURL))
            guard let png, !isClosed, state.url?.host() == pageURL.host() else { return }
            update { $0.favicon = png }
        }
    }

    private func observe() {
        let handler: @Sendable (WKWebView) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromWebView() }  // WebKit posts KVO on the main thread.
        }
        observations = [
            webView.observe(\.url) { wv, _ in handler(wv) },
            webView.observe(\.title) { wv, _ in handler(wv) },
            webView.observe(\.isLoading) { wv, _ in handler(wv) },
            webView.observe(\.estimatedProgress) { wv, _ in handler(wv) },
            webView.observe(\.canGoBack) { wv, _ in handler(wv) },
            webView.observe(\.canGoForward) { wv, _ in handler(wv) },
            webView.observe(\.hasOnlySecureContent) { wv, _ in handler(wv) },
            webView.observe(\.cameraCaptureState) { wv, _ in handler(wv) },
            webView.observe(\.microphoneCaptureState) { wv, _ in handler(wv) },
            fullscreenObservation(),
        ]
    }

    private func syncFromWebView() {
        guard !isClosed else { return }
        update { s in
            s.title = webView.title ?? ""
            s.isLoading = webView.isLoading
            s.progress = webView.estimatedProgress
            s.canGoBack = webView.canGoBack
            s.canGoForward = webView.canGoForward
            s.hasOnlySecureContent = webView.hasOnlySecureContent
            s.camera = Self.captureState(webView.cameraCaptureState)
            s.microphone = Self.captureState(webView.microphoneCaptureState)
            // Same-document navigations (pushState, #fragment) change the URL without a commit. Accept
            // them only within the committed origin and never while a navigation is pending (SR-016).
            if let url = webView.url, !provisionalInFlight, s.url != nil,
                SecurityOrigin(url: url) == SecurityOrigin(url: s.url)
            {
                s.url = url
            }
        }
    }

    private static func captureState(_ state: WKMediaCaptureState) -> CaptureState {
        switch state {
        case .active: .active
        case .muted: .muted
        case .none: .none
        @unknown default: .none
        }
    }

    private func trigger(for action: WKNavigationAction) -> NavigationPolicy.Trigger {
        if let pending = pendingUserURL, action.request.url == pending { return .userTyped }
        switch action.navigationType {
        case .linkActivated: return .linkClick
        case .backForward, .reload: return .userTyped
        case .formSubmitted, .formResubmitted, .other: return .script
        @unknown default: return .script
        }
    }

    private static func origin(of frame: WKFrameInfo) -> SecurityOrigin {
        let o = frame.securityOrigin
        guard !o.host.isEmpty else { return .opaque }
        return SecurityOrigin(scheme: o.protocol, host: o.host, port: o.port == 0 ? nil : o.port)
    }

    // MARK: Downloads

    func setDevToolsEnabled(_ enabled: Bool) {
        webView.isInspectable = enabled  // adds "Inspect Element" to the page's context menu (SEC-056)
    }

    func showDevTools() -> Bool { false }  // no public API to open Web Inspector; the context menu does

    func cancelDownload(_ id: UUID) {
        guard let download = downloadObjects[id] else { return }
        cancelledDownloads.insert(id)
        // WebKit doesn't call `didFailWithError` after `cancel`, so report it here (once: finishDownload forgets the ID).
        download.cancel { [weak self] _ in
            Task { @MainActor in self?.finishDownload(download, .cancelled) }
        }
    }

    private func adopt(_ download: WKDownload) {
        download.delegate = self
        let id = UUID()
        downloadIDs[ObjectIdentifier(download)] = id
        downloadObjects[id] = download
        downloadObservations[id] = download.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            let received = progress.completedUnitCount
            let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
            MainActor.assumeIsolated {
                self?.emit(.download(DownloadEvent(id: id, state: .progress(received: received, total: total))))
            }
        }
    }

    private func finishDownload(_ download: WKDownload, _ state: DownloadEvent.State) {
        guard let id = downloadIDs.removeValue(forKey: ObjectIdentifier(download)) else { return }
        downloadObservations.removeValue(forKey: id)?.invalidate()
        downloadDestinations[id] = nil
        downloadObjects[id] = nil
        let wasCancelled = cancelledDownloads.remove(id) != nil
        emit(.download(DownloadEvent(id: id, state: wasCancelled ? .cancelled : state)))
    }

    // MARK: Pure helpers (unit-tested)

    /// How an authentication challenge is handled. Server-trust challenges are **always** left to the
    /// system: Nera never overrides certificate validation (SR-002).
    enum ChallengeHandling: Equatable { case systemDefault, askUser }

    static func challengeHandling(for method: String) -> ChallengeHandling {
        switch method {
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest: .askUser
        default: .systemDefault
        }
    }

    /// Maps a failed navigation to a certificate error reason, if it is one.
    static func certificateReason(for error: NSError) -> CertificateErrorReason? {
        guard error.domain == NSURLErrorDomain else { return nil }
        switch error.code {
        case NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid: return .dateInvalid
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot: return .untrusted
        default: return nil
        }
    }

    /// Errors that aren't failures from the user's point of view.
    static func isIgnorable(_ error: NSError) -> Bool {
        (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == WKError.errorDomain && error.code == 102)  // "frame load interrupted" when a navigation becomes a download
    }
}

// MARK: - WKNavigationDelegate

extension WebKitPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let target = navigationAction.request.url else { return .cancel }
        if navigationAction.shouldPerformDownload { return .download }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let trigger = trigger(for: navigationAction)
        if isMainFrame, target == pendingUserURL { pendingUserURL = nil }
        switch policy.decide(target, trigger: trigger, isMainFrame: isMainFrame) {
        case .allow:
            return .allow
        case .upgrade(let upgraded):
            if isMainFrame { emit(.upgradedToHTTPS(from: target)) }
            start(upgraded)
            return .cancel
        case .block(let reason):
            emit(.navigationBlocked(target, reason))
            return .cancel
        case .askToOpenExternally(let ext):
            requestExternalApp(ext)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType { return .download }
        if navigationResponse.isForMainFrame,
            let http = navigationResponse.response as? HTTPURLResponse,
            let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
            disposition.lowercased().hasPrefix("attachment")
        {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        adopt(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        provisionalInFlight = true
        emit(.navigationStarted(webView.url))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        provisionalInFlight = false
        resetMediaFrames()
        update {
            if $0.url?.host() != webView.url?.host() { $0.favicon = nil }  // another site: its own icon
            $0.url = webView.url
        }
        emit(.navigationCommitted(webView.url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncFromWebView()
        emit(.navigationFinished(webView.url))
        loadFavicon()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        provisionalInFlight = false
        handleFailure(error as NSError)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleFailure(error as NSError)
    }

    private func handleFailure(_ error: NSError) {
        syncFromWebView()
        guard !Self.isIgnorable(error) else { return }
        let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if let reason = Self.certificateReason(for: error), let url {
            emit(.navigationFailed(url, .certificate(host: url.host() ?? "", reason: reason)))
            // WebKit offers no bypass without overriding trust, which SR-002 forbids.
            let request = CertificateErrorRequest(
                url: url, reason: reason, isBypassAllowed: false,
                decision: Decision(fallback: .reject) { _ in })
            delegate?.page(self, didRequest: .certificateError(request))
        } else {
            emit(.navigationFailed(url, .network(code: error.code, description: error.localizedDescription)))
        }
    }

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        let space = challenge.protectionSpace
        #if DEBUG
            if space.authenticationMethod == NSURLAuthenticationMethodServerTrust, !WebKitEngine.testTrustAnchors.isEmpty,
                let trust = space.serverTrust
            {
                SecTrustSetAnchorCertificates(trust, WebKitEngine.testTrustAnchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
                // swiftlint:disable:next no_trust_override
                if SecTrustEvaluateWithError(trust, nil) { return (.useCredential, URLCredential(trust: trust)) }  // test-trust: DEBUG only
            }
        #endif
        guard Self.challengeHandling(for: space.authenticationMethod) == .askUser else {
            return (.performDefaultHandling, nil)
        }
        let origin = SecurityOrigin(scheme: space.protocol ?? "https", host: space.host, port: space.port)
        let answer = await ask(fallback: AuthenticationResponse.cancel) { decision in
            .authentication(
                AuthenticationRequest(
                    origin: origin, realm: space.realm, isInsecure: !space.receivesCredentialSecurely,
                    previousFailureCount: challenge.previousFailureCount, decision: decision))
        }
        switch answer {
        case .credentials(let user, let password):
            return (.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
        case .cancel:
            return (.rejectProtectionSpace, nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        provisionalInFlight = false
        update {
            $0.isLoading = false
            $0.progress = 0
        }
        emit(.processTerminated(.unknown))
    }
}

// MARK: - WKUIDelegate

extension WebKitPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Only reached with a user gesture (javaScriptCanOpenWindowsAutomatically = false).
        guard !isClosed, let delegate, let engine else { return nil }
        let child = WebKitPage(
            id: UUID(), storage: storage, configuration: configuration, policy: policy.forChildPage,
            delegate: delegate, engine: engine)
        if case .ephemeral = storage { _ = engine.acquireStore(for: storage) }  // child shares the session
        var disposition: NewPageDisposition = (windowFeatures.width != nil || windowFeatures.height != nil) ? .popup : .foregroundTab
        #if os(macOS)
            if disposition == .foregroundTab, navigationAction.modifierFlags.contains(.command) { disposition = .backgroundTab }
        #endif
        let decision = Decision<NewPageDecision>(fallback: .discard) { [weak child] answer in
            if answer == .discard { child?.close() }
        }
        delegate.page(
            self,
            didRequest: .newPage(
                NewPageRequest(
                    page: child, url: navigationAction.request.url,
                    disposition: disposition, decision: decision)))
        return child.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        emit(.closeRequested)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let origin = Self.origin(of: frame)
        _ = await ask(fallback: DialogResponse.cancel) {
            .dialog(DialogRequest(origin: origin, kind: .alert(message: message), decision: $0))
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async
        -> Bool
    {
        let origin = Self.origin(of: frame)
        let answer = await ask(fallback: DialogResponse.cancel) {
            .dialog(DialogRequest(origin: origin, kind: .confirm(message: message), decision: $0))
        }
        if case .ok = answer { return true }
        return false
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let origin = Self.origin(of: frame)
        let answer = await ask(fallback: DialogResponse.cancel) {
            .dialog(DialogRequest(origin: origin, kind: .prompt(message: prompt, defaultText: defaultText), decision: $0))
        }
        if case .ok(let text) = answer { return text ?? "" }
        return nil
    }

    #if os(macOS)
        func webView(
            _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo
        ) async -> [URL]? {
            await ask(fallback: [URL]?.none) {
                .fileChooser(
                    FileChooserRequest(
                        allowsMultiple: parameters.allowsMultipleSelection,
                        allowsDirectories: parameters.allowsDirectories, decision: $0))
            }
        }
    #endif

    // The async form of WebKit's media-capture delegate is named `decideMediaCapturePermissionsFor`.
    // (A `requestMediaCapturePermissionFor` spelling compiles but is never called; the strict
    // warnings-as-errors build catches that mismatch.)
    func webView(
        _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        let kinds: Set<PermissionKind> =
            switch type {
            case .camera: [.camera]
            case .microphone: [.microphone]
            case .cameraAndMicrophone: [.camera, .microphone]
            @unknown default: []
            }
        guard !kinds.isEmpty else { return .deny }
        let requester =
            origin.host.isEmpty
            ? SecurityOrigin.opaque
            : SecurityOrigin(scheme: origin.protocol, host: origin.host, port: origin.port == 0 ? nil : origin.port)
        let answer = await ask(fallback: PermissionDecision.deny) {
            .permission(PermissionRequest(origin: requester, kinds: kinds, decision: $0))
        }
        return answer == .grant ? .grant : .deny
    }
}

// MARK: - WKDownloadDelegate

extension WebKitPage: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return nil }
        let source = download.originalRequest?.url
        let answer = await ask(fallback: DownloadDecision.cancel) {
            .download(
                DownloadRequest(
                    id: id, sourceURL: source, suggestedFilename: suggestedFilename, mimeType: response.mimeType,
                    expectedLength: response.expectedContentLength >= 0 ? response.expectedContentLength : nil,
                    decision: $0))
        }
        switch answer {
        case .saveTo(let url):
            downloadDestinations[id] = url
            return url
        case .cancel:
            finishDownload(download, .cancelled)
            return nil
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = downloadIDs[ObjectIdentifier(download)], let destination = downloadDestinations[id] else { return }
        finishDownload(download, .finished(destination))
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        finishDownload(download, .failed(error.localizedDescription))
    }
}
