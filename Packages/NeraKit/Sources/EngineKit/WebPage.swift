// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import Observation

/// One live web page, usually shown in one tab.
///
/// Pages are created by ``BrowserEngine/makePage(_:delegate:)`` and are `@Observable`: views can
/// read ``state`` directly. Business logic should react to ``WebPageDelegate`` events instead.
@MainActor
public protocol WebPage: AnyObject, Observable {
    /// Same as ``PageConfiguration/id``.
    var id: UUID { get }

    /// Everything the UI shows about the page, as one value.
    var state: PageState { get }

    /// The view the engine renders into. Host it in exactly one place at a time.
    var view: PlatformView { get }

    /// Loads a user-initiated URL (typed, bookmark, restored tab). The engine runs the navigation
    /// policy with trigger `.userTyped` first; blocked URLs never reach the engine's network stack.
    func load(_ url: URL)

    /// Goes back in session history.
    func goBack()

    /// Goes forward in session history.
    func goForward()

    /// Reloads the page.
    func reload()

    /// Stops loading.
    func stop()

    /// Ends the page's HTML full screen (the window left full screen some other way).
    func exitFullscreen()

    /// HTML full screen is shown in a window of the engine's own (WebKit), not by the browser window filling the
    /// screen with the page (Chromium).
    var showsFullscreenInOwnWindow: Bool { get }

    /// Sets page zoom (1.0 = 100%). No-op without ``EngineCapability/pageZoom``.
    func setZoom(_ factor: Double)

    /// Mutes or unmutes the page. No-op without ``EngineCapability/audioControl``.
    func setMuted(_ muted: Bool)

    /// Finds text in the page. Returns no match without ``EngineCapability/findInPage``.
    func find(_ text: String, options: FindOptions) async -> FindResult

    /// Removes find highlighting.
    func clearFindResults()

    /// Downloads `url` without navigating ("Download Linked File"). The engine sends a
    /// ``DownloadRequest`` for the destination. No-op without ``EngineCapability/downloads``.
    func startDownload(_ url: URL)

    /// Allows or forbids developer tools for this page (off by default; the user turns them on, SEC-056).
    func setDevToolsEnabled(_ enabled: Bool)

    /// Opens developer tools for this page. Returns `false` if the engine can't open them programmatically
    /// (WebKit: use the page's "Inspect Element" context menu item instead).
    func showDevTools() -> Bool

    /// Cancels a running download. The engine then sends a ``DownloadEvent`` with ``DownloadEvent/State/cancelled``.
    /// Unknown or finished IDs are ignored.
    func cancelDownload(_ id: UUID)

    /// Runs one of **Nera's own** scripts in the page's top frame and returns its result as a string (objects as
    /// JSON), or `nil` if it failed or the page has no document yet. Never pass page-supplied text as `script`.
    /// Used by SiteStyles, the mini player and password setup; scripts must not assume they run in an isolated world.
    func evaluate(_ script: String) async -> String?

    /// Stops all activity and releases engine resources. The page sends no events afterwards.
    func close()
}

/// Receives a page's events and requests. All calls happen on the main actor.
@MainActor
public protocol WebPageDelegate: AnyObject {
    /// ``WebPage/state`` changed.
    func pageDidChangeState(_ page: any WebPage)

    /// Something happened that the app may react to (navigation lifecycle, crash, download progress…).
    func page(_ page: any WebPage, didEmit event: PageEvent)

    /// The page needs an answer (permission, dialog, download destination…). Answer it through the
    /// request's ``Decision``. If the request is dropped without an answer, the safe default applies.
    func page(_ page: any WebPage, didRequest request: PageRequest)
}

/// Everything the UI shows about a page.
public struct PageState: Equatable, Sendable {
    /// The **committed** URL. Never shows a pending URL from a page-initiated navigation, so a page
    /// can't make the address bar lie while a slow navigation is in flight (SR-016).
    public var url: URL?
    /// Page title.
    public var title: String = ""
    /// Whether a navigation is in progress.
    public var isLoading = false
    /// Load progress, 0...1.
    public var progress: Double = 0
    /// Whether ``WebPage/goBack()`` would do something.
    public var canGoBack = false
    /// Whether ``WebPage/goForward()`` would do something.
    public var canGoForward = false
    /// `true` when every resource of the committed page was loaded over a secure connection.
    public var hasOnlySecureContent = false
    /// Current zoom factor.
    public var zoom: Double = 1
    /// The site's icon as PNG (≤ 64 px), once the engine has it. Cleared when the page moves to another site.
    public var favicon: Data?
    /// Whether the page is playing audio (requires ``EngineCapability/audioControl``).
    public var isAudible = false
    /// Whether the page is muted.
    public var isMuted = false
    /// Camera use (requires ``EngineCapability/mediaCaptureIndicators``).
    public var camera: CaptureState = .none
    /// Microphone use (requires ``EngineCapability/mediaCaptureIndicators``).
    public var microphone: CaptureState = .none

    /// Creates a state; every field defaults to an idle, empty page.
    public init(url: URL? = nil, title: String = "") {
        self.url = url
        self.title = title
    }
}

/// Camera or microphone capture state.
public enum CaptureState: Equatable, Sendable {
    /// Not in use.
    case none
    /// Capturing.
    case active
    /// Granted but paused.
    case muted
}

/// Options for ``WebPage/find(_:options:)``.
public struct FindOptions: Equatable, Sendable {
    /// Search backwards from the current match.
    public var backwards = false
    /// Match case.
    public var caseSensitive = false
    /// Wrap around at the end of the page.
    public var wraps = true

    /// Default options: forward, case-insensitive, wrapping.
    public init(backwards: Bool = false, caseSensitive: Bool = false, wraps: Bool = true) {
        self.backwards = backwards
        self.caseSensitive = caseSensitive
        self.wraps = wraps
    }
}

/// Result of ``WebPage/find(_:options:)``.
public struct FindResult: Equatable, Sendable {
    /// Whether a match was found and highlighted.
    public var matchFound: Bool
    /// Number of matches, when the engine reports it (Chromium).
    public var matchCount: Int?
    /// 1-based index of the highlighted match, when reported.
    public var activeMatch: Int?

    /// Creates a result.
    public init(matchFound: Bool, matchCount: Int? = nil, activeMatch: Int? = nil) {
        self.matchFound = matchFound
        self.matchCount = matchCount
        self.activeMatch = activeMatch
    }
}

extension WebPage {
    /// Engines without HTML full screen have nothing to end.
    public func exitFullscreen() {}

    /// Engines show HTML full screen in the browser window unless they say otherwise.
    public var showsFullscreenInOwnWindow: Bool { false }
}
