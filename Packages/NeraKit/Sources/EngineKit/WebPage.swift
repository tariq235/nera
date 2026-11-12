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

    /// Reloads the page and everything on it from the network, skipping the cache (Hard Reload, ⇧⌘R).
    func reloadIgnoringCache()

    /// Stops loading.
    func stop()

    /// Ends the page's HTML full screen (the window left full screen some other way).
    func exitFullscreen()

    /// Opens the Mac's print panel for the page (File › Print).
    func printPage()

    /// The page as PNG: what's on screen, or the whole page when `fullPage` (Capture). nil when it can't.
    func capture(fullPage: Bool) async -> Data?

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

    /// Like ``evaluate(_:)``, but the script runs as if the user had just clicked the page, so it may call what
    /// the web allows only after a click (Picture in Picture), and a promise it returns is awaited. Only for Nera's
    /// own scripts acting on the user's behalf (switching tabs).
    func evaluateAsUserGesture(_ script: String) async -> String?

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
    /// Engines that can't skip their cache reload as usual.
    public func reloadIgnoringCache() { reload() }

    /// Engines without HTML full screen have nothing to end.
    public func exitFullscreen() {}

    /// Engines that can't run a script as a click run it as a plain script.
    public func evaluateAsUserGesture(_ script: String) async -> String? { await evaluate(script) }

    /// Engines without printing print nothing.
    public func printPage() {}

    /// Engines without captures capture nothing.
    public func capture(fullPage: Bool) async -> Data? { nil }

    /// Engines show HTML full screen in the browser window unless they say otherwise.
    public var showsFullscreenInOwnWindow: Bool { false }
}

/// Capturing a whole page: its size from the page, and how far it may be drawn (GPU textures stop around 16,000 px).
public enum PageCapture {
    /// A script answering `[width, height]` of the whole document in CSS pixels, as JSON.
    public static let sizeScript = """
        JSON.stringify([Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0),
          Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)])
        """

    /// What to draw: the page's top-left `width` × `height` CSS pixels at `scale`.
    public struct Plan: Equatable, Sendable {
        /// Width in CSS pixels.
        public var width: Double
        /// Height in CSS pixels.
        public var height: Double
        /// Pixels per CSS pixel.
        public var scale: Double

        /// A plan.
        public init(width: Double, height: Double, scale: Double) {
            self.width = width
            self.height = height
            self.scale = scale
        }
    }

    /// The size to draw (capped) and the scale: Retina when it fits, else 1.
    public static func plan(fromSizeScript answer: String?) -> Plan? {
        guard let data = answer?.data(using: .utf8), let size = try? JSONDecoder().decode([Double].self, from: data), size.count == 2,
            size[0] > 0, size[1] > 0
        else { return nil }
        let scale = size[1] * 2 <= maxPixels ? 2.0 : 1.0
        return Plan(width: min(size[0], maxPixels / scale), height: min(size[1], maxPixels / scale), scale: scale)
    }

    /// The tallest capture drawn, in pixels.
    public static let maxPixels = 16_000.0
}
