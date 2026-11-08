// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
public import Foundation

/// A cookie for ``ChromiumBackend/setCookies(_:storageKey:persistent:)`` (the app target sees only this module).
public typealias ChromiumCookie = WebCookie

/// What ``ChromiumEngine`` needs from Chromium (ADR-0010).
///
/// NeraKit contains no CEF code: the macOS app implements this port with its ObjC++ CEF bridge
/// (`Apps/macOS/Chromium`), and tests use a fake. The shape mirrors the bridge proven in the CEF prototype,
/// with no CEF types. All calls happen on the main actor (CEF's UI thread is the AppKit main thread).
@MainActor
public protocol ChromiumBackend: AnyObject {
    /// `true` once CEF initialized successfully.
    var isRunning: Bool { get }
    /// e.g. "CEF 156.0.15 / Chromium 156.0.8078.80".
    var version: String { get }
    /// Creates one browser. Pages with the same `storageKey` share cookies and storage; `persistent`
    /// selects disk storage (a profile) over memory-only storage (a private session).
    /// `passkeys`: whether the page may expose `PublicKeyCredential` (an authenticator is available).
    func makePage(storageKey: String, persistent: Bool, passkeys: Bool, events: any ChromiumPageEvents) -> any ChromiumPageHandle
    /// Deletes cookies and cached data of one storage key.
    func removeData(storageKey: String, persistent: Bool) async
    /// Adds cookies to one storage key. Returns how many Chromium accepted.
    func setCookies(_ cookies: [WebCookie], storageKey: String, persistent: Bool) async -> Int
    /// The cookies of `site` and its subdomains in one storage key.
    func cookies(forSite site: String, storageKey: String, persistent: Bool) async -> [WebCookie]
}

/// One Chromium browser, created by ``ChromiumBackend/makePage(storageKey:persistent:passkeys:events:)``.
@MainActor
public protocol ChromiumPageHandle: AnyObject {
    /// The view Chromium renders into.
    var view: PlatformView { get }
    /// Starts a browser-initiated navigation (already approved by the navigation policy).
    func load(_ url: String)
    /// Goes back in history.
    func goBack()
    /// Goes forward in history.
    func goForward()
    /// Reloads.
    func reload()
    /// Stops loading.
    func stop()
    /// Page zoom, 1.0 = 100%.
    func setZoomFactor(_ factor: Double)
    /// Mutes or unmutes audio.
    func setMuted(_ muted: Bool)
    /// Starts (`findNext` false) or continues a find; results arrive through
    /// ``ChromiumPageEvents/findMatches(_:active:isFinal:)``.
    func find(_ text: String, forward: Bool, matchCase: Bool, findNext: Bool)
    /// Clears find highlighting.
    func stopFinding()
    /// Downloads a URL without navigating.
    func startDownload(_ url: String)
    /// Adds or removes "Inspect Element" in the page's context menu.
    func setDevToolsEnabled(_ enabled: Bool)
    /// Opens DevTools in their own window.
    func showDevTools()
    /// Runs one of Nera's scripts in the top frame; the result as a string (objects as JSON), `nil` on failure.
    func evaluate(_ script: String) async -> String?
    /// Cancels a running download; a cancelled ``ChromiumDownloadProgress`` follows.
    func cancelDownload(_ id: UInt32)
    /// Closes the browser. No events arrive afterwards.
    func close()
}

/// What started a navigation, mapped from Chromium's transition type.
public enum ChromiumNavigationTrigger: Sendable, Equatable {
    /// Nera's own load, back/forward or reload.
    case userTyped
    /// A link activated with a user gesture.
    case linkClick
    /// Anything the page did without a gesture.
    case script
    /// A server or client redirect.
    case redirect
}

/// Why a renderer process ended.
public enum ChromiumTermination: Sendable, Equatable {
    /// It crashed.
    case crashed
    /// It was killed.
    case killed
    /// It ran out of memory.
    case outOfMemory
    /// Anything else.
    case other
}

/// The kind of JavaScript dialog.
public enum ChromiumDialogKind: Sendable, Equatable {
    /// `alert()`.
    case alert
    /// `confirm()`.
    case confirm
    /// `prompt()`.
    case prompt
}

/// A permission a site asks Chromium for.
public enum ChromiumPermissionKind: Sendable, Hashable {
    /// Camera.
    case camera
    /// Microphone.
    case microphone
    /// Geolocation.
    case location
    /// Notifications.
    case notifications
    /// Clipboard read.
    case clipboardRead
}

/// A download Chromium wants a destination for.
public struct ChromiumDownloadInfo: Sendable, Equatable {
    /// Chromium's id for this download (later progress callbacks carry it).
    public var id: UInt32
    /// Source URL.
    public var url: String
    /// Suggested file name. Untrusted.
    public var suggestedName: String
    /// MIME type, empty if unknown.
    public var mimeType: String
    /// Total bytes, 0 or less if unknown.
    public var totalBytes: Int64

    /// Creates the info.
    public init(id: UInt32, url: String, suggestedName: String, mimeType: String, totalBytes: Int64) {
        self.id = id
        self.url = url
        self.suggestedName = suggestedName
        self.mimeType = mimeType
        self.totalBytes = totalBytes
    }
}

/// Progress of a download.
public struct ChromiumDownloadProgress: Sendable, Equatable {
    /// Chromium's download id.
    public var id: UInt32
    /// Bytes received.
    public var received: Int64
    /// Total bytes, 0 or less if unknown.
    public var total: Int64
    /// Finished successfully.
    public var isComplete: Bool
    /// Cancelled.
    public var isCanceled: Bool
    /// Interrupted (network or disk error).
    public var isInterrupted: Bool
    /// Destination path.
    public var path: String

    /// Creates the progress value.
    public init(
        id: UInt32, received: Int64, total: Int64, isComplete: Bool = false, isCanceled: Bool = false,
        isInterrupted: Bool = false, path: String = ""
    ) {
        self.id = id
        self.received = received
        self.total = total
        self.isComplete = isComplete
        self.isCanceled = isCanceled
        self.isInterrupted = isInterrupted
        self.path = path
    }
}

/// Callbacks from one Chromium browser, on the main actor.
@MainActor
public protocol ChromiumPageEvents: AnyObject {
    /// Synchronous policy check for every frame navigation. Return `false` to cancel it.
    func shouldNavigate(to url: String, mainFrame: Bool, trigger: ChromiumNavigationTrigger) -> Bool
    /// A main-frame navigation committed.
    func didCommit(url: String)
    /// The main frame finished loading.
    func didFinish(url: String, httpStatus: Int)
    /// A main-frame load failed (`code` is Chromium's net error, e.g. -3 for aborted).
    func didFail(url: String, code: Int, description: String)
    /// The title changed.
    func titleChanged(_ title: String)
    /// The page's favicon (PNG) was downloaded.
    func faviconChanged(_ png: Data)
    /// A frame made a WebAuthn request through Nera's shim. `reply(ok, payload)`: JSON, or `"Name|message"`.
    func webAuthnRequested(kind: String, json: String, frameURL: String, topURL: String, reply: @escaping @MainActor (Bool, String) -> Void)
    /// Loading state and history availability changed.
    func loadingChanged(isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    /// Load progress, 0...1.
    func progressChanged(_ progress: Double)
    /// A JavaScript dialog. Call `reply` once; if it's released uncalled, the dialog is cancelled.
    func dialog(
        kind: ChromiumDialogKind, originURL: String, message: String, defaultText: String,
        reply: @escaping @MainActor (_ ok: Bool, _ text: String?) -> Void)
    /// A site asks for permissions. Call `reply` once; if it's released uncalled, the request is denied.
    func permissionRequested(
        origin: String, kinds: Set<ChromiumPermissionKind>, reply: @escaping @MainActor (_ granted: Bool) -> Void)
    /// A download needs a destination. Reply with a file path, or `nil` to cancel.
    func downloadRequested(_ info: ChromiumDownloadInfo, reply: @escaping @MainActor (_ path: String?) -> Void)
    /// A download made progress, finished, failed or was cancelled.
    func downloadUpdated(_ progress: ChromiumDownloadProgress)
    /// Find results.
    func findMatches(_ count: Int, active: Int, isFinal: Bool)
    /// The renderer process ended.
    func processTerminated(_ reason: ChromiumTermination)
}
