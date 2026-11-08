// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
import Foundation
public import Security
import SecurityPolicy
import WebKit

/// WebKit engine adapter: the engine on iOS/iPadOS (App Store rule 2.5.6) and the fallback engine
/// on macOS (ADR-0006).
///
/// This is one of only two modules allowed to import WebKit. Nothing WebKit-specific leaves it:
/// the rest of Nera sees `BrowserEngine` and `WebPage` only.
@MainActor
public final class WebKitEngine: BrowserEngine {
    #if DEBUG
        /// Debug test runs only: extra trust anchors (the local test server's CA, security conformance).
        /// Validation still runs in full (expiry, host name, chain). Never compiled into Release builds.
        nonisolated(unsafe) public static var testTrustAnchors: [SecCertificate] = []
    #endif

    /// Identity: `"webkit"`, with the system WebKit version.
    public let descriptor: EngineDescriptor

    /// What WebKit supports through public API. Notably missing: audio control (no public mute API),
    /// certificate-error bypass (would require overriding trust, forbidden by SR-002), extensions,
    /// and programmatic developer tools.
    public let capabilities: EngineCapabilities

    private var persistentStores: [UUID: WKWebsiteDataStore] = [:]
    private var ephemeralStores: [UUID: (store: WKWebsiteDataStore, pages: Int)] = [:]

    /// Creates the engine. Cheap: no web content process starts until the first page loads.
    public init() {
        let version = Bundle(for: WKWebView.self).infoDictionary?["CFBundleVersion"] as? String ?? "system"
        descriptor = EngineDescriptor(id: "webkit", displayName: "WebKit", version: version, isAvailable: true)
        var caps: EngineCapabilities = [
            .findInPage, .pageZoom, .mediaCaptureIndicators, .downloads, .javaScriptDialogs,
            .httpAuthentication, .mediaPermissionRequests, .childPages,
        ]
        #if os(macOS)
            caps.insert(.fileChooser)
        #endif
        capabilities = caps
    }

    /// Creates a WebKit page with Nera's hardened defaults.
    public func makePage(_ configuration: PageConfiguration, delegate: any WebPageDelegate) -> any EngineKit.WebPage {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = acquireStore(for: configuration.storage)
        config.preferences.isFraudulentWebsiteWarningEnabled = true  // Safe Browsing (SR-017)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false  // popups need a gesture (SR-015)
        config.upgradeKnownHostsToHTTPS = true
        config.mediaTypesRequiringUserActionForPlayback = .audio
        #if os(macOS)
            config.preferences.isElementFullscreenEnabled = true
        #else
            config.allowsInlineMediaPlayback = true
        #endif
        return WebKitPage(
            id: configuration.id, storage: configuration.storage, configuration: config,
            policy: configuration.policy, delegate: delegate, engine: self)
    }

    /// Deletes a scope's website data. Persistent stores are removed from disk.
    public func removeWebsiteData(for scope: StorageScope) async {
        switch scope {
        case .persistent(let id):
            persistentStores[id] = nil
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        case .ephemeral(let id):
            ephemeralStores[id] = nil
        }
    }

    /// A site's cookies in a storage scope (none for a private session that has ended).
    public func cookies(forSite site: String, in scope: StorageScope) async -> [WebCookie] {
        guard let store = existingStore(for: scope) else { return [] }
        return await store.httpCookieStore.allCookies().compactMap { http in
            let cookie = WebCookie(
                domain: http.domain, name: http.name, value: http.value, path: http.path, expires: http.expiresDate,
                isSecure: http.isSecure, isHTTPOnly: http.isHTTPOnly, sameSite: http.sameSitePolicy?.rawValue)
            return cookie.belongs(to: site) ? cookie : nil
        }
    }

    /// Adds cookies to a storage scope's store.
    public func addCookies(_ cookies: [WebCookie], in scope: StorageScope) async -> Int {
        if case .ephemeral(let id) = scope, ephemeralStores[id] == nil {
            // A private tab moving here: its session's store is made now, and its page joins it right after.
            ephemeralStores[id] = (WKWebsiteDataStore.nonPersistent(), 0)
        }
        guard let dataStore = existingStore(for: scope) else { return 0 }
        let store = dataStore.httpCookieStore
        var added = 0
        for cookie in cookies {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: cookie.domain, .path: cookie.path, .name: cookie.name, .value: cookie.value,
            ]
            if cookie.isSecure { properties[.secure] = "TRUE" }
            if let expires = cookie.expires { properties[.expires] = expires }
            if cookie.isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            switch cookie.sameSite {
            case "Lax": properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
            case "Strict": properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
            default: break
            }
            guard let http = HTTPCookie(properties: properties) else { continue }
            await store.setCookie(http)
            added += 1
        }
        return added
    }

    // MARK: Store lifetime

    func acquireStore(for scope: StorageScope) -> WKWebsiteDataStore {
        switch scope {
        case .persistent(let id):
            if let store = persistentStores[id] { return store }
            let store = WKWebsiteDataStore(forIdentifier: id)
            persistentStores[id] = store
            return store
        case .ephemeral(let id):
            let entry = ephemeralStores[id] ?? (WKWebsiteDataStore.nonPersistent(), 0)
            ephemeralStores[id] = (entry.store, entry.pages + 1)
            return entry.store
        }
    }

    /// The store of a scope, if it exists (never creates a private session's store).
    func existingStore(for scope: StorageScope) -> WKWebsiteDataStore? {
        switch scope {
        case .persistent: acquireStore(for: scope)  // persistent stores aren't counted
        case .ephemeral(let id): ephemeralStores[id]?.store
        }
    }

    func releaseStore(for scope: StorageScope) {
        guard case .ephemeral(let id) = scope, let entry = ephemeralStores[id] else { return }
        // The last page of a private session is gone: drop its in-memory store entirely.
        ephemeralStores[id] = entry.pages <= 1 ? nil : (entry.store, entry.pages - 1)
    }

    /// Number of live ephemeral sessions (for tests).
    var ephemeralSessionCount: Int { ephemeralStores.count }
}
