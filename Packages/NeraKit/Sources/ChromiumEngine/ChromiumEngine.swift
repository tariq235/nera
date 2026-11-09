// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
import Foundation
import Observation
import SecurityPolicy

/// Chromium engine adapter for macOS, embedded via CEF (ADR-0006, ADR-0009, ADR-0010).
///
/// Hosting is **embedded** (each page is a Chromium view inside Nera's own window; ADR-0009). The adapter
/// is pure Swift: CEF lives behind ``ChromiumBackend``, which the macOS app provides. Without a running
/// backend the engine reports `EngineDescriptor.isAvailable` `false` and the engine registry keeps using the
/// next engine (WebKit), so builds without CEF (iOS, plain `swift test`) work unchanged.
@MainActor
public final class ChromiumEngine: BrowserEngine {
    private let backend: (any ChromiumBackend)?

    /// Identity: `"chromium"`, available while the backend is running. Read at use time: the app builds its
    /// engine list before CEF starts (CEF needs the NSApplication to exist first).
    public var descriptor: EngineDescriptor {
        guard let backend else {
            return EngineDescriptor(id: "chromium", displayName: "Chromium", version: "not bundled on this build", isAvailable: false)
        }
        return EngineDescriptor(id: "chromium", displayName: "Chromium", version: backend.version, isAvailable: backend.isRunning)
    }

    /// What this adapter implements so far. Missing capabilities degrade explicitly (AP-9).
    public var capabilities: EngineCapabilities {
        descriptor.isAvailable
            ? [.javaScriptDialogs, .downloads, .findInPage, .pageZoom, .mediaPermissionRequests, .extensions, .webAuthnBridge] : []
    }

    /// Creates the engine. `backend` is the app's CEF bridge; `nil` means "not bundled on this build".
    /// Handles WebAuthn (passkeys) for every page; without one, pages get `NotAllowedError` at once.
    public var webAuthenticator: (any WebAuthenticator)?

    /// Creates the engine. `webAuthenticator`: the system passkey bridge (docs/security/passkeys.md).
    public init(backend: (any ChromiumBackend)? = nil, webAuthenticator: (any WebAuthenticator)? = nil) {
        self.backend = backend
        self.webAuthenticator = webAuthenticator
    }

    /// Creates a Chromium page, or a page that reports `engineUnavailable` when there's no backend.
    public func makePage(_ configuration: PageConfiguration, delegate: any WebPageDelegate) -> any WebPage {
        guard let backend, descriptor.isAvailable else { return UnavailablePage(id: configuration.id, delegate: delegate) }
        return ChromiumPage(configuration: configuration, backend: backend, delegate: delegate, webAuthenticator: webAuthenticator)
    }

    /// Deletes cookies and cached data for a storage scope.
    public func removeWebsiteData(for scope: StorageScope) async {
        guard let backend else { return }
        let (key, persistent) = ChromiumPage.storageKey(for: scope)
        await backend.removeData(storageKey: key, persistent: persistent)
    }

    /// Adds cookies to a storage scope's store.
    public func addCookies(_ cookies: [WebCookie], in scope: StorageScope) async -> Int {
        guard let backend else { return 0 }
        let (key, persistent) = ChromiumPage.storageKey(for: scope)
        return await backend.setCookies(cookies, storageKey: key, persistent: persistent)
    }

    /// A site's cookies in a storage scope.
    public func cookies(forSite site: String, in scope: StorageScope) async -> [WebCookie] {
        guard let backend, descriptor.isAvailable else { return [] }
        let (key, persistent) = ChromiumPage.storageKey(for: scope)
        return await backend.cookies(forSite: site, storageKey: key, persistent: persistent)
    }
}

/// One Chromium page on Nera's engine contract.
@MainActor
@Observable
final class ChromiumPage: WebPage {
    let id: UUID
    private(set) var state = PageState()
    @ObservationIgnored private weak var delegate: (any WebPageDelegate)?
    @ObservationIgnored private let policy: NavigationPolicy
    @ObservationIgnored weak var webAuthenticator: (any WebAuthenticator)?
    // Set right after init (the handle needs `self` for its events) and never changed.
    // swiftlint:disable:next implicitly_unwrapped_optional
    @ObservationIgnored private var handle: (any ChromiumPageHandle)!
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var downloads: [UInt32: UUID] = [:]
    @ObservationIgnored private var findContinuation: CheckedContinuation<FindResult, Never>?
    /// The text of the current find session: the same text again moves to the next match.
    @ObservationIgnored private var findText: String?

    var view: PlatformView { handle.view }

    init(
        configuration: PageConfiguration, backend: any ChromiumBackend, delegate: any WebPageDelegate,
        webAuthenticator: (any WebAuthenticator)? = nil
    ) {
        self.webAuthenticator = webAuthenticator
        id = configuration.id
        policy = configuration.policy
        self.delegate = delegate
        let (key, persistent) = Self.storageKey(for: configuration.storage)
        handle = backend.makePage(storageKey: key, persistent: persistent, passkeys: webAuthenticator?.isAvailable ?? false, events: self)
    }

    /// Chromium request contexts are keyed by string: one per profile (disk) or private session (memory).
    static func storageKey(for scope: StorageScope) -> (key: String, persistent: Bool) {
        switch scope {
        case .persistent(let id): (id.uuidString, true)
        case .ephemeral(let id): ("ephemeral-\(id.uuidString)", false)
        }
    }

    // MARK: WebPage

    func load(_ url: URL) {
        guard !isClosed else { return }
        switch policy.decide(url, trigger: .userTyped) {
        case .allow: handle.load(url.absoluteString)
        case .upgrade(let upgraded):
            emit(.upgradedToHTTPS(from: url))
            handle.load(upgraded.absoluteString)
        case .block(let reason): emit(.navigationBlocked(url, reason))
        case .askToOpenExternally: break  // external-app requests: not implemented yet (no capability claimed)
        }
    }

    func goBack() { handle.goBack() }
    func goForward() { handle.goForward() }
    func reload() { handle.reload() }
    func stop() { handle.stop() }
    func exitFullscreen() { handle.exitFullscreen() }

    func setZoom(_ factor: Double) {
        handle.setZoomFactor(factor)
        update { $0.zoom = factor }
    }

    func setMuted(_ muted: Bool) {
        handle.setMuted(muted)
        update { $0.isMuted = muted }
    }

    func find(_ text: String, options: FindOptions) async -> FindResult {
        guard !isClosed else { return FindResult(matchFound: false) }
        findContinuation?.resume(returning: FindResult(matchFound: false))
        return await withCheckedContinuation { continuation in
            findContinuation = continuation
            let findNext = findText == text
            findText = text
            handle.find(text, forward: !options.backwards, matchCase: options.caseSensitive, findNext: findNext)
        }
    }

    func clearFindResults() {
        findText = nil
        handle.stopFinding()
    }

    func startDownload(_ url: URL) {
        guard !isClosed else { return }
        if case .block(let reason) = policy.decide(url, trigger: .userTyped) { return emit(.navigationBlocked(url, reason)) }
        handle.startDownload(url.absoluteString)
    }

    func setDevToolsEnabled(_ enabled: Bool) { handle.setDevToolsEnabled(enabled) }

    func evaluate(_ script: String) async -> String? {
        guard !isClosed else { return nil }
        return await handle.evaluate(script)
    }

    func showDevTools() -> Bool {
        guard !isClosed else { return false }
        handle.showDevTools()
        return true
    }

    func cancelDownload(_ id: UUID) {
        guard let chromiumID = downloads.first(where: { $0.value == id })?.key else { return }
        handle.cancelDownload(chromiumID)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        findContinuation?.resume(returning: FindResult(matchFound: false))
        findContinuation = nil
        // Silence it first: Chromium gives a closing page time to run its unload code (up to about half a second),
        // and its sound would play on until then. Muting takes it off the speakers at once.
        handle.setMuted(true)
        handle.close()
        delegate = nil
    }

    // MARK: Internals

    private func emit(_ event: PageEvent) {
        guard !isClosed else { return }
        delegate?.page(self, didEmit: event)
    }

    private func update(_ change: (inout PageState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        if !isClosed { delegate?.pageDidChangeState(self) }
    }

    /// Chromium can report URLs with characters Foundation rejects (e.g. `data:text/html,<title>A B</title>`).
    /// Escape only those characters; existing escapes and URL syntax are kept.
    static func parseURL(_ string: String) -> URL? {
        if let url = URL(string: string) { return url }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:/?#[]@!$&'()*+,;=%")
        return string.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    static func policyTrigger(_ trigger: ChromiumNavigationTrigger) -> NavigationPolicy.Trigger {
        switch trigger {
        case .userTyped: .userTyped
        case .linkClick: .linkClick
        case .script: .script
        case .redirect: .redirect
        }
    }
}

// MARK: - Events from Chromium

extension ChromiumPage: ChromiumPageEvents {
    func shouldNavigate(to url: String, mainFrame: Bool, trigger: ChromiumNavigationTrigger) -> Bool {
        guard !isClosed, let target = Self.parseURL(url) else { return false }
        switch policy.decide(target, trigger: Self.policyTrigger(trigger), isMainFrame: mainFrame) {
        case .allow:
            if mainFrame { emit(.navigationStarted(target)) }
            return true
        case .upgrade(let upgraded):
            if mainFrame { emit(.upgradedToHTTPS(from: target)) }
            handle.load(upgraded.absoluteString)
            return false
        case .block(let reason):
            emit(.navigationBlocked(target, reason))
            return false
        case .askToOpenExternally:
            return false
        }
    }

    func didCommit(url: String) {
        let committed = Self.parseURL(url)
        update {
            if $0.url?.host() != committed?.host() { $0.favicon = nil }  // another site: its own icon
            $0.url = committed  // committed URL only (SR-016)
        }
        emit(.navigationCommitted(committed))
    }

    func didFinish(url: String, httpStatus: Int) { emit(.navigationFinished(Self.parseURL(url))) }

    func didFail(url: String, code: Int, description: String) {
        guard code != -3 else { return }  // ERR_ABORTED: replaced or cancelled by us, not a failure
        let failed = Self.parseURL(url)
        if (-299)...(-200) ~= code {  // Chromium's certificate errors (net/base/net_error_list.h)
            let reason: CertificateErrorReason =
                switch code {
                case -200: .nameMismatch
                case -201: .dateInvalid
                case -202: .untrusted
                case -206: .revoked
                default: .other("net error \(code)")
                }
            return emit(.navigationFailed(failed, .certificate(host: failed?.host() ?? "", reason: reason)))
        }
        emit(.navigationFailed(failed, .network(code: code, description: description)))
    }

    func titleChanged(_ title: String) {
        // Chromium reports the URL as the title until the page sets one; Nera shows "" then.
        update { $0.title = title == $0.url?.absoluteString ? "" : title }
    }

    func faviconChanged(_ png: Data) { update { $0.favicon = png } }

    func fullscreenChanged(_ fullscreen: Bool) { emit(.fullscreenChanged(fullscreen)) }

    func webAuthnRequested(kind: String, json: String, frameURL: String, topURL: String, reply: @escaping @MainActor (Bool, String) -> Void)
    {
        guard let kind = WebAuthnRequest.Kind(rawValue: kind), !isClosed else { return reply(false, "NotAllowedError|Not allowed.") }
        let origin = SecurityOrigin(url: Self.parseURL(frameURL))
        let top = SecurityOrigin(url: Self.parseURL(topURL))
        // Only secure web origins (HTTPS, or loopback for development) may use WebAuthn.
        guard !origin.isOpaque, origin.isSecure, ["https", "http"].contains(origin.scheme) else {
            return reply(false, "SecurityError|WebAuthn needs a secure page.")
        }
        // Cross-origin iframes would need `allow="publickey-credentials-*"`, which Nera can't see: refuse them.
        guard origin == top || kind == .available else {
            return reply(false, "NotAllowedError|Passkeys aren't available in cross-origin frames.")
        }
        guard let authenticator = webAuthenticator else {
            if kind == .available { return reply(true, "false") }
            return reply(false, "\(WebAuthnResult.unavailable.name)|\(WebAuthnResult.unavailable.message)")
        }
        let request = WebAuthnRequest(kind: kind, optionsJSON: json, origin: origin, topOrigin: top)
        Task { @MainActor in
            switch await authenticator.perform(request) {
            case .success(let payload): reply(true, payload)
            case .failure(let name, let message): reply(false, "\(name)|\(message)")
            }
        }
    }

    func loadingChanged(isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        update {
            $0.isLoading = isLoading
            $0.canGoBack = canGoBack
            $0.canGoForward = canGoForward
        }
    }

    func progressChanged(_ progress: Double) { update { $0.progress = progress } }

    func dialog(
        kind: ChromiumDialogKind, originURL: String, message: String, defaultText: String,
        reply: @escaping @MainActor (Bool, String?) -> Void
    ) {
        guard !isClosed else { return reply(false, nil) }
        let dialogKind: DialogKind =
            switch kind {
            case .alert: .alert(message: message)
            case .confirm: .confirm(message: message)
            case .prompt: .prompt(message: message, defaultText: defaultText)
            }
        // Default-deny: if the UI drops the request, the fallback (.cancel) answers Chromium.
        let decision = Decision<DialogResponse>(fallback: .cancel) { answer in
            switch answer {
            case .ok(let text): reply(true, text)
            case .cancel: reply(false, nil)
            }
        }
        let request = DialogRequest(origin: SecurityOrigin(url: Self.parseURL(originURL)), kind: dialogKind, decision: decision)
        delegate?.page(self, didRequest: .dialog(request))
    }

    func permissionRequested(origin: String, kinds: Set<ChromiumPermissionKind>, reply: @escaping @MainActor (Bool) -> Void) {
        guard !isClosed else { return reply(false) }
        let mapped = Set(
            kinds.map { kind -> PermissionKind in
                switch kind {
                case .camera: .camera
                case .microphone: .microphone
                case .location: .location
                case .notifications: .notifications
                case .clipboardRead: .clipboardRead
                }
            })
        // Default-deny: an unanswered or dropped request answers Chromium with "deny".
        let decision = Decision<PermissionDecision>(fallback: .deny) { reply($0 == .grant) }
        delegate?.page(
            self,
            didRequest: .permission(
                PermissionRequest(origin: SecurityOrigin(url: Self.parseURL(origin)), kinds: mapped, decision: decision)))
    }

    func downloadRequested(_ info: ChromiumDownloadInfo, reply: @escaping @MainActor (String?) -> Void) {
        guard !isClosed else { return reply(nil) }
        let id = UUID()
        downloads[info.id] = id
        let decision = Decision<DownloadDecision>(fallback: .cancel) { [weak self] answer in
            switch answer {
            case .saveTo(let file): reply(file.path)
            case .cancel:
                reply(nil)  // CEF cancels once its callback is released uncalled
                self?.downloads[info.id] = nil
                self?.emit(.download(DownloadEvent(id: id, state: .cancelled)))
            }
        }
        let request = DownloadRequest(
            id: id, sourceURL: Self.parseURL(info.url), suggestedFilename: info.suggestedName,
            mimeType: info.mimeType.isEmpty ? nil : info.mimeType, expectedLength: info.totalBytes > 0 ? info.totalBytes : nil,
            decision: decision)
        delegate?.page(self, didRequest: .download(request))
    }

    func downloadUpdated(_ progress: ChromiumDownloadProgress) {
        guard let id = downloads[progress.id] else { return }
        let state: DownloadEvent.State
        if progress.isComplete {
            state = .finished(URL(fileURLWithPath: progress.path))
        } else if progress.isCanceled {
            state = .cancelled
        } else if progress.isInterrupted {
            state = .failed("The download was interrupted.")
        } else {
            state = .progress(received: progress.received, total: progress.total > 0 ? progress.total : nil)
        }
        if progress.isComplete || progress.isCanceled || progress.isInterrupted { downloads[progress.id] = nil }
        emit(.download(DownloadEvent(id: id, state: state)))
    }

    func findMatches(_ matches: Int, active: Int, isFinal: Bool) {
        guard isFinal, let continuation = findContinuation else { return }
        findContinuation = nil
        // CEF reports the active match 0-based (conformance C18 pins this); Nera's is 1-based ("1 of 3").
        continuation.resume(
            returning: FindResult(matchFound: matches > 0, matchCount: matches, activeMatch: matches > 0 && active >= 0 ? active + 1 : nil))
    }

    func processTerminated(_ reason: ChromiumTermination) {
        let mapped: ProcessTerminationReason =
            switch reason {
            case .crashed: .crashed
            case .outOfMemory: .memoryPressure
            case .killed, .other: .unknown
            }
        emit(.processTerminated(mapped))
    }
}

/// Page used while the engine is unavailable. Never shown in practice: the registry skips this engine.
@MainActor
@Observable
final class UnavailablePage: WebPage {
    let id: UUID
    private(set) var state = PageState()
    @ObservationIgnored private weak var delegate: (any WebPageDelegate)?
    @ObservationIgnored let view = PlatformView()

    init(id: UUID, delegate: any WebPageDelegate) {
        self.id = id
        self.delegate = delegate
    }

    func load(_ url: URL) { delegate?.page(self, didEmit: .navigationFailed(url, .engineUnavailable)) }
    func goBack() {}
    func goForward() {}
    func reload() {}
    func stop() {}
    func setZoom(_ factor: Double) {}
    func setMuted(_ muted: Bool) {}
    func find(_ text: String, options: FindOptions) async -> FindResult { FindResult(matchFound: false) }
    func clearFindResults() {}
    func startDownload(_ url: URL) {}
    func cancelDownload(_ id: UUID) {}
    func setDevToolsEnabled(_ enabled: Bool) {}
    func showDevTools() -> Bool { false }
    func evaluate(_ script: String) async -> String? { nil }
    func close() { delegate = nil }
}
