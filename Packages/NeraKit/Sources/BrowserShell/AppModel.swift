// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import CommandBar
import Downloads
public import EngineKit
public import Extensions
public import Foundation
import Import
import Observation
public import PageLifecycle
import Permissions
import SecurityPolicy
public import Sidebar
public import Storage

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The app's coordinator: connects the store, the page manager and transient UI state.
///
/// It receives engines through an `EngineRegistry` built by the app target and never names a
/// concrete engine, so replacing WebKit with Chromium requires no change here (AP-1).
@MainActor
@Observable
public final class AppModel: SidebarHost, CommandBarHost {
    /// The library store.
    public let store: BrowserStore
    /// Live pages.
    public let pages: PageManager

    /// Whether the command bar is shown.
    public var isCommandBarPresented = false
    /// What the command bar does on submit.
    public var commandBarDisposition: TabAction.Disposition = .newTab
    /// Whether the sidebar is shown (macOS).
    public var isSidebarVisible = true
    /// The Downloads tray is open (⌥⌘L, or the sidebar's Downloads button).
    public var isDownloadsTrayPresented = false
    /// A private window: memory-only library, one ephemeral session, no history or icon cache on disk.
    public internal(set) var isPrivate = false
    /// The scene id of private windows.
    public static let privateWindowID = "private"
    /// The find bar is showing (⌘F).
    public var isFindBarPresented = false
    /// Text in the find bar.
    public var findQuery = ""
    /// The last find result ("2 of 5"), nil before searching.
    public var findResult: FindResult?
    /// Zoom shown briefly after ⌘+ / ⌘− / ⌘0.
    public var zoomIndicator: Double?
    @ObservationIgnored var zoomIndicatorTask: Task<Void, Never>?
    /// A newer Nera release (from the daily update check).
    public var availableUpdate: (version: String, url: URL)?
    /// Where the automatic update stands (release builds).
    public internal(set) var updateStatus = UpdateStatus.idle
    /// The user chose "Later" on the ready-to-install banner (it installs on the next quit anyway).
    public var isUpdateBannerDismissed = false
    /// "Turn on developer tools?" is showing (⌥⌘I while they're off).
    public var isConfirmingDevTools = false
    /// The bookmark manager is open (⌥⌘B).
    public var isBookmarksPresented = false
    /// The "Import from Browser" sheet is open.
    public var isBrowserImportPresented = false
    /// The History window is open (⌘Y).
    public var isHistoryPresented = false
    /// Tabs whose site's video Chromium can't play (site), from the media probe.
    public internal(set) var mediaSuggestions: [UUID: String] = [:]
    /// Sites the user said "Not now" to this session.
    var dismissedMediaSites: Set<String> = []
    /// Whether Chromium is waiting for the welcome (tests replace this instead of the process-wide flag).
    @ObservationIgnored var chromiumWaitsForWelcome: () -> Bool = { ChromiumStartup.waitsForWelcome }
    /// Sign-ins imported in the welcome before Chromium started (WebKit gets them if Chromium can't start).
    @ObservationIgnored var pendingSignIns: (profileID: UUID, cookies: [WebCookie])?
    /// Pages that currently carry a SiteStyle style sheet.
    @ObservationIgnored var styledPages: Set<UUID> = []
    /// The SiteStyle editor is showing for the current page.
    public var isSiteStyleEditorPresented = false
    /// Zap is picking parts of the current page to hide.
    public var isZapping = false
    /// The link showing in Peek over the current page.
    public var peek: PeekPage?
    /// Pages showing in Little Windows, by page ID (they're not in the tab list until moved into the browser).
    public var littleTabs: [UUID: BrowserCore.Tab] = [:]
    /// A Little Window waiting to be opened by the main window's view.
    public var pendingLittleWindow: UUID?
    /// A background tab the user paused from the mini player (it stays there to be resumed).
    public var pausedMediaTabID: UUID?
    /// Tabs whose video Nera floated out when you left them (AppModel+PictureInPicture.swift).
    @ObservationIgnored var pictureInPictureTabs: Set<UUID> = []
    /// Clear Browsing Data is showing.
    public var isClearDataPresented = false
    /// The Space being edited in the Edit Space sheet.
    public var editingSpaceID: UUID?
    /// The Edit Space sheet is naming a Space just made with +; Cancel removes it again.
    public var isCreatingSpace = false
    /// A two-finger swipe in progress: how far the sidebar's Space has moved (points).
    public var spaceSwipeOffset: CGFloat = 0
    /// A two-finger swipe on the page: -1...1 toward back (negative) or forward; ±1 means "let go to go".
    public var pageSwipeProgress: Double = 0
    /// The sidebar is shown floating over the page (hidden sidebar, pointer at the window's left edge).
    public var isSidebarPeeking = false
    /// Site icons by host.
    @ObservationIgnored public let favicons: FaviconStore
    /// Where downloads and captures are saved (nil: downloads are off).
    @ObservationIgnored public let downloadsDirectory: URL?
    /// Installed Chrome extensions.
    @ObservationIgnored public let extensionStore: ExtensionStore
    /// Bumped when extensions change, so views reload the list.
    public internal(set) var extensionsRevision = 0
    /// Extensions changed since launch: they apply when Chromium restarts.
    public internal(set) var needsRelaunchForExtensions = false
    /// Browsing history (nil when unavailable).
    @ObservationIgnored public let history: HistoryStore?
    /// Bumped when history changes from the UI, so the History view reloads.
    public private(set) var historyRevision = 0

    /// Tells views showing history to reload.
    func historyDidChange() { historyRevision += 1 }
    /// A download finished since the tray was last opened (dot on the Downloads button).
    public var hasUnseenFinishedDownload = false
    /// Whether the Arc import file picker is shown.
    public var isImportingFromArc = false
    /// A one-line message for the notice banner.
    public var notice: String?
    /// File › Capture… is waiting for an area of the page to be chosen.
    public var isCapturing = false
    /// The site controls (the address pill's popover) are open.
    public var isSiteControlsPresented = false
    /// Assistive apps and Chromium pages (A11Y-009, WebAccessibility.swift).
    public var assistive = AssistiveAppsState()
    @ObservationIgnored var safetyBox = SafetyBox()
    /// This window's Space and tab when several browser windows share the library (ADR-0013); nil: the library's.
    var selection: WindowSelection?
    /// The first window's model: the further browser windows' models (WindowRestore.swift).
    @ObservationIgnored var windowModels: [WindowModelRef] = []
    /// Where this window goes when it opens (a window restored at launch).
    @ObservationIgnored var pendingFrame: CGRect?
    #if os(macOS)
        /// The window showing this model (WindowTracker).
        @ObservationIgnored weak var hostWindow: NSWindow?
    #endif
    /// Started in safe mode after repeated failed launches (SEC-054).
    public private(set) var isSafeMode = false

    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private let memoryMonitor = MemoryPressureMonitor()

    /// Creates the coordinator.
    /// - Parameters:
    ///   - store: The library store.
    ///   - registry: Engines available to this app, most preferred first.
    ///   - downloadsDirectory: Where downloads are saved; `nil` disables downloads.
    ///   - history: Browsing history; `nil` records nothing.
    ///   - favicons: Site icon cache.
    ///   - extensions: Installed Chrome extensions.
    public init(
        store: BrowserStore, registry: EngineRegistry, downloadsDirectory: URL?, history: HistoryStore? = nil,
        favicons: FaviconStore = FaviconStore(directory: nil),
        extensions: ExtensionStore = ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "NeraExtensions-\(UUID().uuidString)"))
    ) {
        self.store = store
        self.history = history
        self.favicons = favicons
        self.downloadsDirectory = downloadsDirectory
        self.extensionStore = extensions
        self.pages = PageManager(registry: registry, policy: NavigationPolicy(httpsOnly: store.state.settings.httpsOnly))
        store.effectHandler = { [weak self] effect in
            self?.pages.handle(effect)
            if case .removeProfileData(let profileID) = effect { self?.history?.clear(profileID: profileID) }
        }
        pages.send = { [weak store] action in store?.send(action) }
        pages.profileProvider = { [weak store] id in store?.state.profiles.first { $0.id == id } }
        pages.automaticPermission = { [weak store] tabID, request in
            PermissionPolicy.automaticDecision(origin: request.origin, kinds: request.kinds, profile: store?.state.profile(forTab: tabID))
        }
        if let downloadsDirectory {
            let planner = DownloadPlanner(directory: downloadsDirectory)
            pages.downloadDestination = { planner.destination(for: $0.suggestedFilename) }
            pages.downloadRisk = {
                if case .dangerous(let reason) = DownloadSafety.risk(filename: $0.suggestedFilename, mimeType: $0.mimeType) {
                    return reason
                }
                return nil
            }
            pages.downloadFinished = { [weak self] file in
                try? DownloadSafety.quarantine(file)
                if self?.isDownloadsTrayPresented == false { self?.hasUnseenFinishedDownload = true }
            }
        }
        if let history {
            pages.pageVisited = { profileID, url, title, isNewVisit in
                if isNewVisit {
                    history.recordVisit(url, title: title, profileID: profileID)
                } else {
                    history.updateTitle(url, title: title, profileID: profileID)
                }
            }
        }
        pages.devToolsEnabled = store.state.settings.isDeveloperToolsEnabled
        pages.faviconChanged = { [favicons] host, png in favicons.save(png, forHost: host) }
        pages.zoomForURL = { [weak store] tabID, url in
            guard let host = url.host()?.lowercased() else { return 1 }
            return store?.state.profile(forTab: tabID)?.siteZoom?[host] ?? 1
        }
        memoryMonitor.start { [weak self] level in self?.pages.handleMemoryPressure(level) }
        pages.documentChanged = { [weak self] page in
            self?.applySiteStyle(to: page)
            self?.probeMedia(page)
        }
        pages.childPageInterceptor = { [weak self] opener, child, url in
            self?.peekIfWanted(opener: opener, child: child, url: url) ?? false
        }
        pages.peekRule = { [weak self] tabID, url in self?.linkOpensInPeek(from: tabID, to: url) ?? false }
        pages.openInPeek = { [weak self] opener, url in self?.openInPeek(url, from: opener) }
        pages.visibilityChanged = { [weak self] hidden, shown in self?.tabsVisibilityChanged(hidden: hidden, shown: shown) }
        startBackgroundSweeps()
    }

    /// A browser window sharing `main`'s library, pages and services (see `window(sharing:)`). The page callbacks,
    /// background sweeps and memory monitor stay with `main`.
    init(sharing main: AppModel) {
        store = main.store
        pages = main.pages
        history = main.history
        favicons = main.favicons
        downloadsDirectory = main.downloadsDirectory
        extensionStore = main.extensionStore
        safetyBox = main.safetyBox
    }

    /// Safe mode: nothing loads until the user picks a tab, and the banner says why (SEC-054).
    func enterSafeMode() {
        isSafeMode = true
        send(.tab(.clearSelection))
        notice =
            "Nera started in safe mode after problems at launch: pages aren't reopened automatically"
            + " and the WebKit engine is used. Quit and reopen Nera to leave safe mode."
    }

    // MARK: SidebarHost & CommandBarHost

    /// Opens the command bar.
    public func showCommandBar(_ disposition: TabAction.Disposition) {
        commandBarDisposition = disposition
        isCommandBarPresented = true
    }

    /// Shows the Arc import file picker.
    public func requestArcImport() { isImportingFromArc = true }

    /// Focuses a tab and closes the command bar.
    public func switchToTab(_ id: UUID) {
        isCommandBarPresented = false
        send(.tab(.select(id)))
    }

    /// Closes the command bar.
    public func dismissCommandBar() { isCommandBarPresented = false }

    // MARK: Pages

    /// The oldest request waiting in the selected tab.
    public var currentRequest: PageRequest? {
        state.selectedTabID.flatMap { pages.requests(for: $0).first }
    }

    /// Removes an answered (or abandoned) request from the queue.
    public func finish(_ request: PageRequest) { pages.dismissRequest(request.id) }

    /// The user chose to keep a download Nera flagged as dangerous.
    public func confirmDangerousDownload(_ request: DownloadRequest) {
        if let tabID = state.selectedTabID { pages.startDownload(request, tabID: tabID) }
        pages.dismissRequest(request.id)
    }

    /// Why a pending download was flagged, for the warning card.
    public func downloadRiskReason(_ request: DownloadRequest) -> String {
        if case .dangerous(let reason) = DownloadSafety.risk(filename: request.suggestedFilename, mimeType: request.mimeType) {
            return reason
        }
        return ""
    }

    /// Answers a permission request and remembers the answer for this site in the tab's profile (SEC-040).
    /// - Parameters:
    ///   - request: The page's request.
    ///   - decision: Grant or deny.
    ///   - remember: `false` for "Allow This Time": nothing is saved, so the site asks again next time.
    public func answerPermission(_ request: PermissionRequest, _ decision: PermissionDecision, remember: Bool = true) {
        request.decision.resolve(decision)
        if remember, let tabID = state.selectedTabID, let profile = state.profile(forTab: tabID) {
            for action in PermissionPolicy.remember(decision, origin: request.origin, kinds: request.kinds, profileID: profile.id) {
                send(action)
            }
        }
        pages.dismissRequest(request.id)
    }

    /// Forgets every remembered permission decision for a site (default: the current one), or for all sites,
    /// in the current profile. Profile-wide defaults are kept.
    public func resetSitePermissions(allSites: Bool = false, origin: String? = nil) {
        guard let profile = state.currentProfile else { return }
        if allSites { return send(.library(.resetSitePermissions(profileID: profile.id, origin: nil))) }
        guard let target = origin ?? currentSiteOrigin else { return }
        send(.library(.resetSitePermissions(profileID: profile.id, origin: target)))
    }

    /// The current tab's origin as permission settings store it (`https://host[:port]`), for web pages only.
    public var currentSiteOrigin: String? {
        guard let url = state.selectedTab?.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return PermissionPolicy.originKey(SecurityOrigin(url: url))
    }

    /// Sets (or with `nil`, forgets) one site's decision for one permission in the current profile.
    public func setSitePermission(origin: String, kind: SitePermissionKind, setting: SitePermissionSetting?) {
        guard let profile = state.currentProfile else { return }
        send(.library(.setSitePermission(profileID: profile.id, origin: origin, kind: kind, setting: setting)))
    }

    /// "Don't allow sites to use your camera" for the current profile.
    public func setPermissionBlockedByDefault(_ kind: SitePermissionKind, _ blocked: Bool) {
        setSitePermission(origin: SitePermission.allSites, kind: kind, setting: blocked ? .deny : nil)
    }

    /// Back.
    public func goBack() { selectedPage?.goBack() }
    /// Forward.
    public func goForward() { selectedPage?.goForward() }
    /// Reload.
    public func reload() {
        guard let page = selectedPage else { return }
        if page.state.isLoading { page.stop() } else { page.reload() }
    }

    /// ⌘W.
    public func closeSelectedTab() {
        if let id = state.selectedTabID { send(.tab(.close(id))) }
    }

    /// ⌘D.
    public func togglePinSelectedTab() {
        if let id = state.selectedTabID { send(.tab(.togglePin(id))) }
    }

    /// Opens a URL in the app registered for its scheme (after the user confirmed).
    public func openExternally(_ url: URL) {
        guard !url.isFileURL else { return }  // never open local files (or downloads) on a page's behalf (SEC-044)
        #if os(macOS)
            NSWorkspace.shared.open(url)
        #else
            UIApplication.shared.open(url)
        #endif
    }

    // MARK: Import

    /// Imports Spaces from an Arc `StorableSidebar.json` the user picked.
    public func importArcSidebar(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let profileID = state.currentProfile?.id else { return }
            let result = try ArcImporter.parse(data: data, profileID: profileID)
            send(.library(.importLibrary(spaces: result.spaces, favorites: result.favorites)))
            let r = result.report
            // naming: import-reference
            notice = "Imported \(r.spaces) spaces, \(r.tabs) tabs, \(r.folders) folders and \(r.favorites) favorites from Arc."
        } catch {
            notice = "That file isn't an Arc sidebar file (StorableSidebar.json)."  // naming: import-reference
        }
    }

    // MARK: Background

    private func startBackgroundSweeps() {
        sweepTask = Task { [weak self] in
            var minutes = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                minutes += 1
                guard let self else { return }
                self.pages.suspendIdlePages()
                if minutes % 15 == 0 { self.send(.library(.archiveSweep)) }
            }
        }
    }
}

extension AppModel {
    /// The selected tab's URL.
    public var currentURLString: String { state.selectedTab?.url?.absoluteString ?? "" }
}
