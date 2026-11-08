// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import SecurityPolicy

/// A rendering engine: WebKit, Chromium, or a test double.
///
/// This protocol and ``WebPage`` are the **only** way the rest of Nera talks to an engine
/// (architecture principle AP-1, ADR-0006). Swapping one engine for another must not change any
/// UI or business logic: only the composition root (the app target) decides which engines exist.
///
/// Implementations must:
/// - run `SecurityPolicy.NavigationPolicy` for every navigation, using the policy in ``PageConfiguration``;
/// - never override certificate validation (SR-002);
/// - deliver every user-facing request through ``WebPageDelegate/page(_:didRequest:)`` with a
///   ``Decision`` whose fallback is the safe answer;
/// - keep website data of each ``StorageScope`` isolated from every other scope;
/// - pass the shared conformance suite (`EngineConformance`) for every capability they declare.
@MainActor
public protocol BrowserEngine: AnyObject {
    /// Identity and availability of this engine.
    var descriptor: EngineDescriptor { get }

    /// Optional features this engine supports. Features check these instead of the engine type.
    var capabilities: EngineCapabilities { get }

    /// Creates a page. The page holds `delegate` weakly and sends it every event and request.
    func makePage(_ configuration: PageConfiguration, delegate: any WebPageDelegate) -> any WebPage

    /// Deletes all website data (cookies, storage, cache) for a storage scope.
    func removeWebsiteData(for scope: StorageScope) async

    /// Adds cookies to a profile's store (sign-ins imported from another browser). Returns how many were accepted.
    func addCookies(_ cookies: [WebCookie], to profileID: UUID) async -> Int

    /// Adds cookies to any storage scope (a tab moving here from the other engine). Returns how many were accepted.
    func addCookies(_ cookies: [WebCookie], in scope: StorageScope) async -> Int

    /// The cookies of `site` and its subdomains in a storage scope, so a tab can move to the other engine
    /// signed in. Their values are secrets: never logged.
    func cookies(forSite site: String, in scope: StorageScope) async -> [WebCookie]
}

extension BrowserEngine {
    /// Adds imported sign-ins to a profile's (persistent) store.
    public func addCookies(_ cookies: [WebCookie], to profileID: UUID) async -> Int {
        await addCookies(cookies, in: .persistent(profileID))
    }
}

extension WebCookie {
    /// Whether this cookie belongs to `site` or one of its subdomains.
    public func belongs(to site: String) -> Bool {
        let host = (domain.hasPrefix(".") ? String(domain.dropFirst()) : domain).lowercased()
        let site = site.lowercased()
        return host == site || host.hasSuffix("." + site)
    }
}

/// A cookie handed to an engine, e.g. a sign-in imported from another browser. Its value is a secret.
public struct WebCookie: Sendable, Hashable {
    /// Domain as stored (a leading dot covers subdomains).
    public var domain: String
    /// Name.
    public var name: String
    /// Value.
    public var value: String
    /// Path.
    public var path: String
    /// Expiry; `nil` for a session cookie.
    public var expires: Date?
    /// HTTPS only.
    public var isSecure: Bool
    /// Hidden from page scripts.
    public var isHTTPOnly: Bool
    /// "None", "Lax", "Strict", or `nil` when unspecified.
    public var sameSite: String?

    /// Creates a cookie.
    public init(
        domain: String, name: String, value: String, path: String, expires: Date?, isSecure: Bool, isHTTPOnly: Bool, sameSite: String?
    ) {
        self.domain = domain
        self.name = name
        self.value = value
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
    }

    /// The address the cookie belongs to (its domain without a leading dot).
    public var url: URL? {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return URL(string: "\(isSecure ? "https" : "http")://\(host)\(path.hasPrefix("/") ? path : "/")")
    }
}

/// Identity of an engine.
public struct EngineDescriptor: Hashable, Sendable {
    /// Stable identifier, e.g. `"webkit"`. Matches `BrowserCore.EngineID.rawValue`.
    public var id: String
    /// User-facing name, e.g. "WebKit".
    public var displayName: String
    /// Engine version, e.g. the WebKit or Chromium version string.
    public var version: String
    /// `false` while an engine is compiled in but can't run yet (e.g. Chromium before CEF is bundled).
    /// Unavailable engines are skipped by the engine registry.
    public var isAvailable: Bool

    /// Creates a descriptor.
    public init(id: String, displayName: String, version: String, isAvailable: Bool) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.isAvailable = isAvailable
    }
}

/// An optional engine feature. Features degrade explicitly when a capability is missing (AP-9).
public enum EngineCapability: String, CaseIterable, Hashable, Sendable {
    /// Find in page.
    case findInPage
    /// Page zoom.
    case pageZoom
    /// Mute a page's audio, and report whether it is playing audio.
    case audioControl
    /// Report camera/microphone capture state.
    case mediaCaptureIndicators
    /// Downloads (navigations that become downloads, and ``WebPage/startDownload(_:)``).
    case downloads
    /// `alert` / `confirm` / `prompt` dialogs routed to the app.
    case javaScriptDialogs
    /// `<input type=file>` routed to the app.
    case fileChooser
    /// HTTP Basic/Digest authentication routed to the app.
    case httpAuthentication
    /// Camera/microphone permission requests routed to the app.
    case mediaPermissionRequests
    /// Certificate errors the user may choose to bypass (on non-HSTS hosts).
    case certificateErrorBypass
    /// Child pages that keep their opener relationship (`window.open`, OAuth popups).
    case childPages
    /// Developer tools.
    case devTools
    /// Browser extensions.
    case extensions
    /// WebAuthn routed through Nera's ``WebAuthenticator`` (Chromium). WebKit talks to the system itself.
    case webAuthnBridge
}

/// The set of capabilities an engine supports.
public typealias EngineCapabilities = Set<EngineCapability>

/// How a page is configured when created.
public struct PageConfiguration: Sendable {
    /// The page's identity. Nera uses the tab's ID, so pages and tabs map one to one.
    public var id: UUID
    /// Which website data store the page uses.
    public var storage: StorageScope
    /// The navigation policy the engine must enforce for this page.
    public var policy: NavigationPolicy

    /// Creates a configuration.
    public init(id: UUID, storage: StorageScope, policy: NavigationPolicy) {
        self.id = id
        self.storage = storage
        self.policy = policy
    }
}

/// An isolated website data store (cookies, local storage, cache, service workers).
public enum StorageScope: Hashable, Sendable {
    /// Saved to disk. Keyed by profile ID; one store per profile per engine.
    case persistent(UUID)
    /// Memory only, shared by every page with the same session ID (one private window), and
    /// destroyed when the last such page closes.
    case ephemeral(UUID)
}
