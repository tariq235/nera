// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Engine-neutral rules for which navigations are allowed (SR-010 … SR-015).
///
/// Every engine adapter must call ``decide(_:trigger:isMainFrame:)`` for every navigation, so
/// security behavior is identical on WebKit and Chromium and is unit-tested once.
public struct NavigationPolicy: Sendable, Equatable {
    /// What started a navigation. Determines how much it is trusted.
    public enum Trigger: Sendable, Equatable {
        /// The user typed or pasted it into the command bar, or picked a bookmark.
        case userTyped
        /// The user clicked a link on a page.
        case linkClick
        /// Page script, meta refresh, or form submission without a user gesture.
        case script
        /// Server redirect (3xx).
        case redirect
    }

    /// The outcome of a policy check.
    public enum Decision: Sendable, Equatable {
        /// Proceed as requested.
        case allow
        /// Proceed, but to this upgraded (https) URL instead.
        case upgrade(URL)
        /// Refuse; show the reason to the user.
        case block(Reason)
        /// Hand off to another app (mailto:, zoommtg:, …) only after the user confirms.
        case askToOpenExternally(URL)
    }

    /// Why a navigation was blocked. The raw value is user-facing text.
    public enum Reason: String, Sendable, Equatable {
        /// `javascript:` / `vbscript:` URL.
        case javascriptURL = "javascript: URLs can't be opened from the address bar or from pages."
        /// Top-level `data:` URL not typed by the user.
        case dataURLTopLevel = "Pages can't open data: URLs in a new top-level page (common phishing trick)."
        /// `file:` URL requested by web content.
        case fileURLFromWeb = "Web pages can't open files on your computer."
        /// `user:password@host` URL.
        case credentialsInURL = "Links with embedded usernames or passwords are blocked (common phishing trick)."
        /// Missing or unsupported scheme, or an app link without a user gesture.
        case unsupportedScheme = "This kind of link isn't supported."
        /// The site opens with Nera's other engine (``EngineRoute``): the page is made again there, before any
        /// request is sent. Never shown to the user.
        case otherEngine = "This site opens with Nera's other engine."
        /// A link from a Favorite or pinned tab to another site (``PeekRoute``): it opens in Peek over the page, and
        /// the tab stays on its own site. Stopped before any request; never shown to the user.
        case openInPeek = "This link opens in Peek."
        /// The address must be checked with Safe Browsing first (``SafetyGate``): held before any request, then loaded
        /// or replaced by a warning. Never shown to the user as a blocked navigation.
        case awaitingSafetyCheck = "Checking whether this site is safe."
    }

    /// Upgrade main-frame `http:` navigations to `https:` (SR-001).
    public var httpsOnly: Bool
    /// Hosts the user chose to allow over plain HTTP ("Continue to Site (Not Secure)"), for this app session.
    /// Shared by every copy of the policy, so a choice applies to pages that already exist.
    public let allowedOverHTTP: HTTPAllowList
    /// The hosts allowed over plain HTTP.
    public var httpExceptions: Set<String> { allowedOverHTTP.hosts }
    /// Extension popup pages Nera opens itself may show `chrome-extension://` pages. Never set for web pages.
    public var allowsExtensionPages = false
    /// Which sites this page's engine hands to the other engine (streaming sites, the user's choices). Set per
    /// page by Nera; child pages (popups) never have one, so they keep their opener.
    public var engineRoute: EngineRoute?
    /// Which link clicks open in Peek instead of in the page (a Favorite's or pinned tab's links to other sites).
    /// Set per page by Nera; child pages never have one.
    public var peekRoute: PeekRoute?
    /// Holds main-frame navigations Safe Browsing must check first (set per page by Nera; popups keep it).
    public var safetyGate: SafetyGate?

    /// This policy for a page opened by another page (a popup or a new window with an opener): no engine route.
    public var forChildPage: NavigationPolicy {
        var policy = self
        policy.engineRoute = nil
        policy.peekRoute = nil
        return policy
    }

    /// Creates a policy.
    public init(httpsOnly: Bool = true, httpExceptions: Set<String> = []) {
        self.httpsOnly = httpsOnly
        self.allowedOverHTTP = HTTPAllowList(httpExceptions)
    }

    static let webSchemes: Set<String> = ["http", "https"]
    static let internalSchemes: Set<String> = ["about", "blob"]

    /// Decides whether `url` may be navigated to.
    /// - Parameters:
    ///   - url: The destination.
    ///   - trigger: What started the navigation.
    ///   - isMainFrame: `false` for iframes and subresources-in-frames.
    public func decide(_ url: URL, trigger: Trigger, isMainFrame: Bool = true) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .block(.unsupportedScheme) }

        if Self.webSchemes.contains(scheme) {
            if url.user() != nil || url.password() != nil, isMainFrame { return .block(.credentialsInURL) }
            // A click on a link that leaves a Favorite's or pinned tab's site opens in Peek (Arc's behavior).
            if isMainFrame, trigger == .linkClick, peekRoute?.wantsPeek(url) == true { return .block(.openInPeek) }
            // Typed URLs (and back/forward) were already given to the right engine by Nera.
            if isMainFrame, trigger != .userTyped, engineRoute?.wantsOtherEngine(url) == true { return .block(.otherEngine) }
            if scheme == "http", httpsOnly, isMainFrame, let host = url.host()?.lowercased(),
                !Self.isLoopback(host), !allowedOverHTTP.contains(host),
                var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            {
                parts.scheme = "https"
                if parts.port == 80 { parts.port = nil }
                if let upgraded = parts.url { return .upgrade(upgraded) }
            }
            // After any upgrade: the address that will really be requested is the one checked.
            if isMainFrame, safetyGate?.holds(url) == true { return .block(.awaitingSafetyCheck) }
            return .allow
        }

        if scheme == "chrome-extension" {
            // Only Nera's own extension popups; a web page or a typed URL never reaches extension pages.
            return allowsExtensionPages ? .allow : .block(.unsupportedScheme)
        }

        switch scheme {
        case "javascript", "vbscript":
            // Bookmarklets would need an explicit opt-in feature; never from typing or pages.
            return .block(.javascriptURL)
        case "data":
            // Subframes and images may use data:, but top-level navigation is only allowed when typed.
            if !isMainFrame || trigger == .userTyped { return .allow }
            return .block(.dataURLTopLevel)
        case "file":
            return trigger == .userTyped ? .allow : .block(.fileURLFromWeb)
        case _ where Self.internalSchemes.contains(scheme):
            return .allow
        default:
            // Custom app schemes need a user gesture and confirmation.
            return trigger == .script || trigger == .redirect ? .block(.unsupportedScheme) : .askToOpenExternally(url)
        }
    }

    /// `true` for localhost and loopback addresses, which stay on plain HTTP for local development.
    public static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}

/// Tells a page's navigation policy which main-frame addresses must wait for a Safe Browsing check. The rule
/// is local and synchronous (a lookup in lists kept on the Mac), so nothing is requested before the verdict.
public final class SafetyGate: @unchecked Sendable, Equatable {
    private let rule: @Sendable (URL) -> Bool

    /// A gate; `rule` answers whether a URL must be checked before it's requested.
    public init(_ rule: @escaping @Sendable (URL) -> Bool) { self.rule = rule }

    /// Whether `url` waits for a check.
    public func holds(_ url: URL) -> Bool { rule(url) }

    /// Same gate object.
    public static func == (a: SafetyGate, b: SafetyGate) -> Bool { a === b }
}

/// Decides which link clicks in a page open in Peek instead (see ``NavigationPolicy/peekRoute``).
public final class PeekRoute: @unchecked Sendable, Equatable {
    private let rule: @Sendable (URL) -> Bool

    /// A route; `rule` answers whether a clicked link opens in Peek. It's called where the engine decides
    /// navigations (the main thread).
    public init(_ rule: @escaping @Sendable (URL) -> Bool) { self.rule = rule }

    /// Whether a click on a link to `url` opens in Peek.
    public func wantsPeek(_ url: URL) -> Bool { rule(url) }

    /// Routes are the same object (a page's policy carries one).
    public static func == (a: PeekRoute, b: PeekRoute) -> Bool { a === b }
}

/// Tells a page's navigation policy which main-frame destinations belong in the other engine.
/// Engine-neutral: Nera supplies the rule; the adapters only see a blocked navigation.
public final class EngineRoute: @unchecked Sendable, Equatable {
    private let rule: @Sendable (URL) -> Bool

    /// A route; `rule` answers whether a URL needs the other engine. It's called where the engine decides
    /// navigations (the main thread).
    public init(_ rule: @escaping @Sendable (URL) -> Bool) { self.rule = rule }

    /// Whether `url` needs the other engine.
    public func wantsOtherEngine(_ url: URL) -> Bool { rule(url) }

    /// Same route object.
    public static func == (a: EngineRoute, b: EngineRoute) -> Bool { a === b }
}

/// Hosts allowed over plain HTTP. A reference shared by every copy of a ``NavigationPolicy``; thread-safe.
public final class HTTPAllowList: @unchecked Sendable, Equatable {
    private let lock = NSLock()
    private var storage: Set<String>

    /// Creates a list.
    public init(_ hosts: Set<String> = []) { storage = Set(hosts.map { $0.lowercased() }) }

    /// The hosts.
    public var hosts: Set<String> { lock.withLock { storage } }

    /// Whether `host` is allowed over HTTP.
    public func contains(_ host: String) -> Bool { lock.withLock { storage.contains(host.lowercased()) } }

    /// Allows `host` over HTTP from now on (this session).
    public func insert(_ host: String) { _ = lock.withLock { storage.insert(host.lowercased()) } }

    /// Same hosts.
    public static func == (a: HTTPAllowList, b: HTTPAllowList) -> Bool { a === b || a.hosts == b.hosts }
}
