// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import EngineKit
public import Foundation
import Observation
public import SecurityPolicy

/// A navigation the policy refused, for the UI banner.
public struct BlockedNavigation: Equatable, Sendable {
    /// The refused URL.
    public var url: URL
    /// Why.
    public var reason: NavigationPolicy.Reason
    /// The tab it happened in.
    public var tabID: UUID

    /// Creates a record.
    public init(url: URL, reason: NavigationPolicy.Reason, tabID: UUID) {
        self.url = url
        self.reason = reason
        self.tabID = tabID
    }
}

/// A download as shown in the UI.
public struct DownloadItem: Identifiable, Equatable, Sendable {
    /// Same as the engine's download ID.
    public var id: UUID
    /// The tab that started it.
    public var tabID: UUID
    /// File name on disk.
    public var filename: String
    /// Latest state; `nil` until the first progress event.
    public var state: DownloadEvent.State?
    /// Where it came from (used by Retry). `nil` for `blob:`/`data:` downloads, which can't be retried.
    public var sourceURL: URL?
    /// Where it's being saved.
    public var destination: URL?
    /// When it started.
    public var startedAt: Date

    /// Creates an item.
    public init(
        id: UUID, tabID: UUID, filename: String, state: DownloadEvent.State? = nil, sourceURL: URL? = nil, destination: URL? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.tabID = tabID
        self.filename = filename
        self.state = state
        self.sourceURL = sourceURL
        self.destination = destination
        self.startedAt = startedAt
    }

    /// Still running (no final state yet).
    public var isActive: Bool {
        switch state {
        case nil, .progress?: true
        default: false
        }
    }

    /// Finished, failed or cancelled downloads with a web source can be started again.
    public var canRetry: Bool {
        guard let scheme = sourceURL?.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        switch state {
        case .failed?, .cancelled?: return true
        default: return false
        }
    }

    /// 0…1 when the size is known.
    public var fractionCompleted: Double? {
        guard case .progress(let received, let total?)? = state, total > 0 else { return nil }
        return min(1, Double(received) / Double(total))
    }

    /// The saved file, once finished.
    public var fileURL: URL? {
        if case .finished(let url)? = state { return url }
        return nil
    }
}

/// Owns every live page, engine-neutrally.
///
/// - Creates pages lazily when a tab is shown, in the engine the tab's profile uses.
/// - Caps memory: LRU eviction, idle suspension, and memory-pressure handling. A discarded page
///   reloads from the tab's URL when shown again.
/// - Turns page events into store actions, and queues page requests per tab for the UI.
/// - Applies engine-neutral policies: dialog flood protection, child-page adoption, crash tracking.
///
/// Dropping a request (discarding its tab, closing its page) applies the request's safe fallback.
@MainActor
@Observable
public final class PageManager {
    /// Last navigation the policy blocked; the UI shows it as a banner.
    public var lastBlocked: BlockedNavigation?
    /// Tabs whose content process exited; the UI shows a "page crashed" view with Reload.
    public private(set) var crashedTabs: Set<UUID> = []
    /// Requests waiting for the user, per tab, oldest first.
    public private(set) var pendingRequests: [UUID: [PageRequest]] = [:]
    /// Downloads started this session, newest last.
    public private(set) var downloads: [DownloadItem] = []

    /// The engines.
    @ObservationIgnored public let registry: EngineRegistry
    /// Navigation policy given to every new page.
    @ObservationIgnored public var policy: NavigationPolicy
    /// Maximum number of live pages; least recently used ones are discarded beyond it.
    @ObservationIgnored public var maxLivePages: Int
    /// Background pages unused for this long are discarded by ``suspendIdlePages(now:)``.
    @ObservationIgnored public var idleTimeout: TimeInterval
    /// Sends actions to the store (wired by the shell).
    @ObservationIgnored public var send: (Action) -> Void = { _ in }
    /// Chooses where downloads are saved (wired by the shell). `nil` or a `nil` result cancels the download.
    @ObservationIgnored public var downloadDestination: ((DownloadRequest) -> URL?)?
    /// Why a download is dangerous, or `nil` when it's safe. Dangerous downloads wait for the user's
    /// confirmation instead of being saved (SEC-045). Set by the app from `DownloadSafety`.
    @ObservationIgnored public var downloadRisk: (DownloadRequest) -> String? = { _ in nil }
    /// A page in a persistent profile committed a new URL (`isNewVisit`) or got its title: the app records history.
    /// Never called for private (ephemeral) pages.
    @ObservationIgnored public var pageVisited: (_ profileID: UUID, _ url: URL, _ title: String, _ isNewVisit: Bool) -> Void = {
        _, _, _, _ in
    }
    /// Called when a download finished writing its file (the app quarantines it, SEC-044).
    @ObservationIgnored public var downloadFinished: (URL) -> Void = { _ in }
    /// Answers a permission request without asking (remembered decision, insecure origin), or returns `nil`
    /// to ask the user. Set by the app from `PermissionPolicy` (SEC-040). Default: always ask.
    @ObservationIgnored public var automaticPermission: (_ tabID: UUID, _ request: PermissionRequest) -> PermissionDecision? = { _, _ in nil
    }
    /// Tabs on screen in each browser window (PageManager+Windows.swift).
    @ObservationIgnored var shownTabs: [ObjectIdentifier: Set<UUID>] = [:]
    /// Pages shown outside the tab list (Peek, Little Windows): never discarded to save memory while shown.
    @ObservationIgnored public var keptPageIDs: Set<UUID> = []
    /// The engine each page runs in, and the profile it was made for (to move a page when a site needs the other
    /// engine).
    @ObservationIgnored var pageEngines: [UUID: String] = [:]
    @ObservationIgnored var pageProfiles: [UUID: Profile] = [:]
    /// The current version of a profile, by ID (wired by the shell); pages otherwise keep the one they were made with.
    @ObservationIgnored public var profileProvider: (UUID) -> Profile? = { _ in nil }
    /// Tabs whose page is being moved to the other engine.
    @ObservationIgnored var movingTabs: Set<UUID> = []
    /// Pages whose last main-frame load failed, by tab: the app shows an error page over them.
    public private(set) var loadFailures: [UUID: LoadFailure] = [:]
    /// The `http:` address a page was last upgraded from (HTTPS-Only), to offer it if the secure load fails.
    @ObservationIgnored var upgradedFrom: [UUID: URL] = [:]
    /// How long an upgraded (HTTPS-Only) load may take to start showing the page before Nera stops it and offers
    /// to continue over HTTP: some sites never answer on HTTPS at all (Chrome's HTTPS-First waits 3 s).
    @ObservationIgnored public var httpsFallbackDelay: Duration = .seconds(5)
    /// Called when a page commits a new document and again when it finishes loading (SiteStyles restyle it).
    @ObservationIgnored public var documentChanged: ((any WebPage) -> Void)?
    /// Safe Browsing's gate, given to new pages of the engines in ``safetyGateEngines`` (set by the shell).
    @ObservationIgnored public var safetyGate: SafetyGate?
    /// Engines whose pages Nera checks itself (WebKit has Apple's own warning).
    @ObservationIgnored public var safetyGateEngines: Set<String> = []
    /// A navigation was held for a Safe Browsing check (the shell asks Google, then loads or warns).
    @ObservationIgnored public var safetyHold: ((any WebPage, URL) -> Void)?
    /// The address each page is held at, until it navigates elsewhere or is released.
    @ObservationIgnored public private(set) var heldNavigations: [UUID: URL] = [:]

    /// Ends a hold: the page's next navigation replaces it.
    public func releaseHold(_ pageID: UUID) { heldNavigations[pageID] = nil }
    /// Offered every child page a tab opens in a tab (not popups). Returning `true` means the app shows the
    /// page itself (Peek); the page stays live here but no tab is created for it.
    @ObservationIgnored public var childPageInterceptor: ((_ openerID: UUID, _ childID: UUID, _ url: URL?) -> Bool)?
    /// The tab currently on screen. Never evicted or suspended.
    @ObservationIgnored public private(set) var activeTabID: UUID?

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var pages: [UUID: any WebPage] = [:]
    @ObservationIgnored private var lastUsed: [UUID: Date] = [:]
    @ObservationIgnored private var lastReported: [UUID: Reported] = [:]
    @ObservationIgnored private var scopes: [UUID: StorageScope] = [:]
    /// A page in a persistent profile got its site icon (PNG): the app caches it by host.
    @ObservationIgnored public var faviconChanged: (_ host: String, _ png: Data) -> Void = { _, _ in }
    @ObservationIgnored private var reportedFavicon: [UUID: Data] = [:]
    /// The zoom to use for a page at a URL (the profile's per-site zoom); applied when a page moves to another site.
    @ObservationIgnored public var zoomForURL: (_ tabID: UUID, _ url: URL) -> Double = { _, _ in 1 }
    @ObservationIgnored private var zoomedHost: [UUID: String] = [:]
    /// Storage for pages created without an explicit scope: a private window uses `.ephemeral(session)` for all.
    @ObservationIgnored public var defaultStorage: StorageScope?
    /// Developer tools allowed for every page (the user's setting, SEC-056).
    public var devToolsEnabled = false {
        didSet { for page in pages.values { page.setDevToolsEnabled(devToolsEnabled) } }
    }
    /// Last URL recorded in history per page (separate from `lastReported`, which starts at the tab's URL).
    @ObservationIgnored private var visitedURL: [UUID: URL] = [:]
    @ObservationIgnored private var dialogThrottles: [UUID: DialogThrottle] = [:]

    private struct Reported: Equatable {
        var url: URL?
        var title: String
    }

    /// Creates a page manager.
    public init(
        registry: EngineRegistry, policy: NavigationPolicy = NavigationPolicy(), maxLivePages: Int = 24,
        idleTimeout: TimeInterval = 30 * 60, clock: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.policy = policy
        self.maxLivePages = maxLivePages
        self.idleTimeout = idleTimeout
        self.clock = clock
    }

    /// Number of live pages.
    public var livePageCount: Int { pages.count }

    /// The live page for a tab, if it has one.
    public func existingPage(for tabID: UUID) -> (any WebPage)? { pages[tabID] }

    /// Requests waiting for the user in a tab.
    public func requests(for tabID: UUID) -> [PageRequest] { pendingRequests[tabID] ?? [] }

    /// Returns the tab's live page, creating it in the profile's engine and loading the tab's URL if
    /// needed. Marks the tab as the active one.
    /// `makeActive` false: a page shown outside the tab list (a Little Window), which leaves the active tab alone.
    public func page(for tab: Tab, profile: Profile, storage: StorageScope? = nil, makeActive: Bool = true) -> any WebPage {
        if makeActive { activeTabID = tab.id }
        lastUsed[tab.id] = clock()
        if let page = pages[tab.id] { return page }
        let engine = registry.engine(for: profile, url: tab.url)  // a site may need the other engine (SiteEngines)
        var pagePolicy = policy
        pagePolicy.engineRoute = route(for: tab.id)
        if safetyGateEngines.contains(engine.descriptor.id) { pagePolicy.safetyGate = safetyGate }
        let configuration = PageConfiguration(
            id: tab.id, storage: storage ?? defaultStorage ?? .persistent(profile.id), policy: pagePolicy)
        let page = engine.makePage(configuration, delegate: self)
        page.setDevToolsEnabled(devToolsEnabled)
        pages[tab.id] = page
        scopes[tab.id] = configuration.storage
        pageEngines[tab.id] = engine.descriptor.id
        pageProfiles[tab.id] = profile
        lastReported[tab.id] = Reported(url: tab.url, title: tab.title)
        if let url = tab.url { page.load(url) }
        evictIfNeeded()
        return page
    }

    /// Executes a store effect.
    public func handle(_ effect: Effect) {
        switch effect {
        case .load(let tabID, let url):
            crashedTabs.remove(tabID)
            if otherEngine(for: tabID, url: url) != nil {
                move(tabID, to: url)  // typed into a tab whose page runs in the other engine
            } else {
                pages[tabID]?.load(url)  // No page yet: it loads `tab.url` when first shown.
            }
        case .discardPage(let tabID):
            discard(tabID)
        case .removeProfileData(let profileID):
            for engine in registry.engines {
                Task { await engine.removeWebsiteData(for: .persistent(profileID)) }
            }
        }
    }

    /// Destroys every page (a private window closing: its session's data goes with the last page).
    public func discardAll() {
        for id in Array(pages.keys) { discard(id) }
    }

    /// The latest version of a page's profile: site engine choices change while pages are open.
    func profile(of tabID: UUID) -> Profile? {
        guard let made = pageProfiles[tabID] else { return nil }
        return profileProvider(made.id) ?? made
    }

    /// The engine `url` needs in a tab's profile, when the tab's page runs in a different one.
    func otherEngine(for tabID: UUID, url: URL?) -> (any BrowserEngine)? {
        guard let url, let profile = profile(of: tabID), let current = pageEngines[tabID] else { return nil }
        let wanted = registry.engine(for: profile, url: url)
        return wanted.descriptor.id == current ? nil : wanted
    }

    /// Lets a tab's page hand navigations to sites that need the other engine back to Nera (they're blocked
    /// before any request and arrive as ``NavigationPolicy/Reason/otherEngine``).
    func route(for tabID: UUID) -> EngineRoute {
        EngineRoute { [weak self] url in
            MainActor.assumeIsolated { self?.otherEngine(for: tabID, url: url) != nil }
        }
    }

    /// Moves a tab's page to the engine `url` needs (a streaming service, or a site the user sent to WebKit):
    /// copies the site's cookies so the tab stays signed in, then makes the page again there and loads `url`.
    /// The tab, its storage scope and whether it's active stay; back/forward history starts over. The old
    /// engine never requested `url`.
    func move(_ tabID: UUID, to url: URL) {
        guard let from = pages[tabID], !movingTabs.contains(tabID), let target = otherEngine(for: tabID, url: url),
            let source = registry.engines.first(where: { $0.descriptor.id == pageEngines[tabID] }),
            let profile = profile(of: tabID), let storage = scopes[tabID]
        else { return }
        movingTabs.insert(tabID)
        from.stop()
        let site = SiteEngines.cookieSite(of: url)
        Task { @MainActor [weak self] in  // not from inside the page's own callback
            if let site {
                let cookies = await source.cookies(forSite: site, in: storage)
                if !cookies.isEmpty { _ = await target.addCookies(cookies, in: storage) }
            }
            guard let self else { return }
            self.movingTabs.remove(tabID)
            guard self.isLive(from) else { return }  // closed or replaced meanwhile
            let wasActive = self.activeTabID == tabID
            self.discard(tabID)
            let tab = Tab(id: tabID, url: url, lastActiveAt: self.clock())
            _ = self.page(for: tab, profile: profile, storage: storage, makeActive: wasActive)
        }
    }

    /// Moves a tab's page to the engine its site now needs, after the user changed a site's engine. A page
    /// already in that engine is left alone. `fallbackURL` (the tab's address) is used before the page's first
    /// load commits.
    public func reopen(_ tabID: UUID, fallbackURL: URL?) {
        guard let url = pages[tabID]?.state.url ?? fallbackURL else { return }
        move(tabID, to: url)
    }

    /// Forgets a page's load failure (the user retried, went back or continued).
    public func clearLoadFailure(_ tabID: UUID) { loadFailures[tabID] = nil }

    /// Destroys a tab's page. Its pending requests are dropped, which applies their safe fallbacks.
    public func discard(_ tabID: UUID) {
        pages.removeValue(forKey: tabID)?.close()
        lastUsed[tabID] = nil
        lastReported[tabID] = nil
        scopes[tabID] = nil
        heldNavigations[tabID] = nil
        visitedURL[tabID] = nil
        zoomedHost[tabID] = nil
        reportedFavicon[tabID] = nil
        dialogThrottles[tabID] = nil
        pendingRequests[tabID] = nil
        crashedTabs.remove(tabID)
        pageEngines[tabID] = nil
        pageProfiles[tabID] = nil
        if activeTabID == tabID { activeTabID = nil }
    }

    /// The engine a live page runs in (`EngineDescriptor.id`).
    public func engineID(of tabID: UUID) -> String? { pageEngines[tabID] }

    /// Recreates a crashed tab's page and reloads its URL.
    public func reloadCrashed(_ tab: Tab, profile: Profile) {
        discard(tab.id)
        _ = page(for: tab, profile: profile)
    }

    /// Removes a request from the queue after the UI answered it. An unanswered request falls back to its safe default.
    public func dismissRequest(_ requestID: UUID) {
        for (tabID, queue) in pendingRequests {
            let remaining = queue.filter { $0.id != requestID }
            if remaining.count != queue.count {
                pendingRequests[tabID] = remaining.isEmpty ? nil : remaining
            }
        }
    }

    /// Hides a finished download from the UI list.
    public func dismissDownload(_ id: UUID) {
        downloads.removeAll { $0.id == id }
    }

    /// Removes every download that isn't running any more (the tray's "Clear").
    public func clearInactiveDownloads() {
        downloads.removeAll { !$0.isActive }
    }

    /// Cancels a running download. It shows as cancelled at once; the engine's own event follows.
    public func cancelDownload(_ id: UUID) {
        guard let i = downloads.firstIndex(where: { $0.id == id }), downloads[i].isActive else { return }
        downloads[i].state = .cancelled
        pages[downloads[i].tabID]?.cancelDownload(id)
    }

    /// Starts a failed or cancelled download again, from its tab's page (or any open page if that tab is gone).
    /// The old entry is replaced by the new download when it starts. Returns `false` if it can't be retried.
    @discardableResult
    public func retryDownload(_ id: UUID) -> Bool {
        guard let item = downloads.first(where: { $0.id == id }), item.canRetry, let url = item.sourceURL,
            let page = pages[item.tabID] ?? pages.values.first
        else { return false }
        downloads.removeAll { $0.id == id }
        page.startDownload(url)
        return true
    }

    /// Frees memory: `.warning` discards the older half of the background pages, `.critical` all of them.
    public func handleMemoryPressure(_ level: MemoryPressureLevel) {
        let background = backgroundPagesOldestFirst()
        let count = level == .critical ? background.count : background.count / 2 + background.count % 2
        background.prefix(count).forEach(discard)
    }

    /// Discards background pages unused for longer than ``idleTimeout``.
    public func suspendIdlePages(now: Date? = nil) {
        let now = now ?? clock()
        for id in backgroundPagesOldestFirst() where now.timeIntervalSince(lastUsed[id] ?? now) > idleTimeout {
            discard(id)
        }
    }

    // MARK: Private

    private func backgroundPagesOldestFirst() -> [UUID] {
        pages.keys.filter { $0 != activeTabID && !visibleTabIDs.contains($0) && !keptPageIDs.contains($0) }.sorted {
            (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast)
        }
    }

    private func evictIfNeeded() {
        let excess = pages.count - maxLivePages
        guard excess > 0 else { return }
        backgroundPagesOldestFirst().prefix(excess).forEach(discard)
    }

    private func isLive(_ page: any WebPage) -> Bool { pages[page.id] === page }

    private func enqueue(_ request: PageRequest, for tabID: UUID) {
        pendingRequests[tabID, default: []].append(request)
    }
}

extension PageManager {
    /// Applies the site's remembered zoom when the page arrives on a different host.
    fileprivate func applySiteZoom(_ page: any WebPage, url: URL?) {
        guard let url, let host = url.host()?.lowercased(), zoomedHost[page.id] != host else { return }
        zoomedHost[page.id] = host
        let factor = zoomForURL(page.id, url)
        if abs(page.state.zoom - factor) > 0.001 { page.setZoom(factor) }
    }

    /// Reports a history visit (new URL) or title update for pages in persistent profiles.
    fileprivate func recordVisit(_ pageID: UUID, url: URL?, title: String) {
        guard case .persistent(let profileID)? = scopes[pageID], let url else { return }
        let isNew = visitedURL[pageID] != url
        visitedURL[pageID] = url
        if isNew || !title.isEmpty { pageVisited(profileID, url, title, isNew) }
    }
}

// MARK: - WebPageDelegate

extension PageManager: WebPageDelegate {
    /// Reports committed URL and title changes to the store (only when they actually change).
    public func pageDidChangeState(_ page: any WebPage) {
        guard isLive(page) else { return }
        if let icon = page.state.favicon, reportedFavicon[page.id] != icon, case .persistent? = scopes[page.id],
            let host = page.state.url?.host()
        {
            reportedFavicon[page.id] = icon
            faviconChanged(host, icon)
        }
        let now = Reported(url: page.state.url, title: page.state.title)
        guard lastReported[page.id] != now else { return }
        lastReported[page.id] = now
        recordVisit(page.id, url: now.url, title: now.title)
        applySiteZoom(page, url: now.url)
        send(.tab(.didUpdate(page.id, url: now.url, title: now.title.isEmpty ? nil : now.title)))
    }

    /// Handles page events.
    public func page(_ page: any WebPage, didEmit event: PageEvent) {
        guard isLive(page) else { return }
        switch event {
        case .navigationCommitted:
            loadFailures[page.id] = nil
            upgradedFrom[page.id] = nil
            dialogThrottles[page.id]?.reset()
            documentChanged?(page)
        case .navigationBlocked(let url, let reason):
            if reason == .otherEngine { return move(page.id, to: url) }
            if reason == .awaitingSafetyCheck {
                heldNavigations[page.id] = url
                return safetyHold?(page, url) ?? ()
            }
            lastBlocked = BlockedNavigation(url: url, reason: reason, tabID: page.id)
        case .processTerminated:
            crashedTabs.insert(page.id)
            pendingRequests[page.id] = nil
        case .download(let event):
            // A download cancelled in the UI stays cancelled whatever the engine reports while it winds down.
            if let i = downloads.firstIndex(where: { $0.id == event.id }), downloads[i].state != .cancelled {
                downloads[i].state = event.state
            }
            if case .finished(let file) = event.state { downloadFinished(file) }
        case .closeRequested:
            send(.tab(.close(page.id)))
        case .navigationFinished:
            documentChanged?(page)
        case .navigationStarted:
            loadFailures[page.id] = nil
            heldNavigations[page.id] = nil
        case .upgradedToHTTPS(let from):
            upgradedFrom[page.id] = from
            let delay = httpsFallbackDelay
            Task { [weak self, weak page] in
                try? await Task.sleep(for: delay)
                guard let self, let page, self.isLive(page), self.upgradedFrom[page.id] == from, self.loadFailures[page.id] == nil
                else { return }
                page.stop()
                var secure = URLComponents(url: from, resolvingAgainstBaseURL: false)
                secure?.scheme = "https"
                self.loadFailures[page.id] = LoadFailure(
                    url: secure?.url ?? from, error: .network(code: -7, description: "Timed out"), upgradedFrom: from)
            }
        case .navigationFailed(let url, let error):
            loadFailures[page.id] = LoadFailure(url: url, error: error, upgradedFrom: upgradedFrom[page.id])
        }
    }

    /// Saves a download to its planned destination. Also used after the user confirms a dangerous one.
    public func startDownload(_ r: DownloadRequest, tabID: UUID) {
        guard let destination = downloadDestination?(r) else { return }  // fallback: cancel
        downloads.append(
            DownloadItem(
                id: r.id, tabID: tabID, filename: destination.lastPathComponent, sourceURL: r.sourceURL, destination: destination,
                startedAt: clock()))
        r.decision.resolve(.saveTo(destination))
    }

    /// Routes page requests: adopts child pages, decides downloads, throttles dialogs, queues the rest for the UI.
    public func page(_ page: any WebPage, didRequest request: PageRequest) {
        guard isLive(page) else { return }  // Dropped: the request falls back to its safe default.
        switch request {
        case .newPage(let r):
            pages[r.page.id] = r.page
            r.page.setDevToolsEnabled(devToolsEnabled)
            scopes[r.page.id] = scopes[page.id]  // child pages share the opener's storage
            pageEngines[r.page.id] = pageEngines[page.id]
            pageProfiles[r.page.id] = pageProfiles[page.id]
            lastUsed[r.page.id] = clock()
            lastReported[r.page.id] = Reported(url: r.url, title: "")
            let intercepted = r.disposition != .popup && childPageInterceptor?(page.id, r.page.id, r.url) == true
            if !intercepted {
                send(.tab(.openChild(id: r.page.id, url: r.url, openerID: page.id, select: r.disposition != .backgroundTab)))
            }
            r.decision.resolve(.adopt)
            evictIfNeeded()
        case .download(let r):
            if downloadRisk(r) != nil {
                enqueue(request, for: page.id)  // the user decides; dropping it cancels
                return
            }
            startDownload(r, tabID: page.id)
        case .dialog(let r):
            var throttle = dialogThrottles[page.id] ?? DialogThrottle()
            let allowed = throttle.shouldShow(at: clock())
            dialogThrottles[page.id] = throttle
            if allowed { enqueue(request, for: page.id) } else { r.decision.resolve(.cancel) }
        case .permission(let r):
            if let decision = automaticPermission(page.id, r) { r.decision.resolve(decision) } else { enqueue(request, for: page.id) }
        case .fileChooser, .authentication, .certificateError, .externalApp:
            enqueue(request, for: page.id)
        }
    }
}

/// Why a page's last main-frame load failed, as the error page explains it.
public struct LoadFailure: Equatable, Sendable {
    /// What went wrong.
    public enum Kind: Equatable, Sendable {
        /// The site's certificate isn't valid. Never bypassable (SEC-005).
        case certificate(CertificateErrorReason)
        /// The site couldn't be reached (offline, DNS, refused, timed out…).
        case unreachable(String)
        /// An `http:` address was upgraded to `https:` and the secure load failed: the site may not support HTTPS.
        case secureConnectionUnavailable(httpURL: URL)
    }

    /// The address that failed.
    public let url: URL?
    /// What went wrong.
    public let kind: Kind

    /// Maps an engine failure; nil for loads that were only cancelled (a new navigation replaced them).
    public init?(url: URL?, error: NavigationError, upgradedFrom: URL? = nil) {
        if case .network(let code, _) = error, [-999, 102, -3].contains(code) { return nil }  // cancelled or replaced
        self.url = url
        if let http = upgradedFrom, http.host()?.lowercased() == url?.host()?.lowercased() {
            kind = .secureConnectionUnavailable(httpURL: http)
            return
        }
        switch error {
        case .certificate(_, let reason): kind = .certificate(reason)
        case .network(_, let description): kind = .unreachable(description)
        case .engineUnavailable: kind = .unreachable("The page engine isn't available.")
        case .other(let description): kind = .unreachable(description)
        }
    }
}
