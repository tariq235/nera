// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Nera's CEF backend: implements ChromiumEngine's ChromiumBackend port over the ObjC++ bridge
// (ADR-0010). Started by ChromiumBootstrap; injected into ChromiumEngine by the composition root.
import AppKit
import BrowserShell
import ChromiumEngine

#if DEBUG
    import EngineConformance
#endif

@MainActor
final class CEFBackend: ChromiumBackend {
    static let shared = CEFBackend()

    /// Running, or waiting to start after the welcome (pages and cookies made meanwhile wait for it).
    var isRunning: Bool { NRAChromium.isStarted || ChromiumStartup.waitsForWelcome }
    var version: String { NRAChromium.versionString() }

    /// Unpacked extension folders to load at start (set by the composition root from the extension store).
    var extensionPaths: [String] = []
    /// The profile whose pages run extensions (Chromium loads them into its startup profile only).
    var extensionsProfile: UUID?
    /// Chromium's data folder, once started.
    private(set) var rootPath: String?

    /// Starts CEF. Profile data lives under Application Support/<bundle id>/Chromium, and cookies are
    /// encrypted with a Keychain item of Nera's own, per bundle id (test builds never touch the real one).
    @discardableResult
    func start() -> Bool {
        guard !NRAChromium.isStarted else { return true }
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.nera.browser"
        // Automated runs (UI tests, the engine self-test; Debug builds only) get a throwaway profile, like their
        // in-memory library (UI tests, self-tests, demo screenshots), and Chromium's mock keychain: ad-hoc test builds change signature every build,
        // which would make the real Keychain item prompt each time. A shipped Nera never takes this path.
        // Benchmark runs (NERA_BENCH=1, any build) too: they must never touch the user's Keychain or profile.
        let benchmark = ProcessInfo.processInfo.environment["NERA_BENCH"] == "1"
        #if DEBUG
            let automated =
                benchmark || ProcessInfo.processInfo.environment["NERA_UI_TEST"] != nil
                || CommandLine.arguments.contains("--engine-self-test") || CommandLine.arguments.contains("--demo")
        #else
            let automated = benchmark
        #endif
        let root: URL
        if automated {
            #if DEBUG
                let name = benchmark ? "NeraBenchChromium" : "NeraTestChromium"
            #else
                let name = "NeraBenchChromium"  // the only automated run a release build has
            #endif
            root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            root = support.appending(path: bundleID).appending(path: "Chromium")
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rootPath = root.path
        Self.removeStaleSingletonLock(in: root, bundleID: bundleID)
        if !automated, let main = extensionsProfile {
            ExtensionStartup.repairMainProfile(chromiumRoot: root, profileID: main)  // sign-ins stranded by builds ≤ 8
        }
        ExtensionStartup.prepareNativeMessagingHosts(chromiumRoot: root)
        var extensions = extensionPaths
        #if DEBUG
            if let probe = ProcessInfo.processInfo.environment["NERA_DEBUG_EXTENSIONS"] {
                extensions += probe.split(separator: ",").map(String.init)
                extensionsProfile = extensionsProfile ?? EngineConformanceProfiles.extensions
            }
        #endif
        return NRAChromium.start(
            withCachePath: root.path, keychainService: "Nera Safe Storage (\(bundleID))", mockKeychain: automated,
            extensionPaths: extensions, extensionsProfile: extensionsProfile?.uuidString)
    }

    /// Chromium's profile lock (`SingletonLock` → "host-pid") survives a crash or force-quit. After a restart
    /// that pid can belong to an unrelated process, and Chromium would then believe Nera is already running
    /// and start without a window. macOS already keeps Nera to one instance per bundle id, so a lock whose pid
    /// isn't a running Nera is stale: remove it (and its socket and cookie links).
    static func removeStaleSingletonLock(in root: URL, bundleID: String) {
        let fm = FileManager.default
        let lock = root.appending(path: "SingletonLock")
        guard let target = try? fm.destinationOfSymbolicLink(atPath: lock.path),
            let pid = target.split(separator: "-").last.flatMap({ Int32($0) })
        else { return }
        let owner = NSRunningApplication(processIdentifier: pid)
        if owner?.bundleIdentifier == bundleID, pid != ProcessInfo.processInfo.processIdentifier { return }  // really running
        for name in ["SingletonLock", "SingletonSocket", "SingletonCookie"] {
            try? fm.removeItem(at: root.appending(path: name))
        }
    }

    func shutdown() { NRAChromium.shutdown() }

    func makePage(storageKey: String, persistent: Bool, passkeys: Bool, events: any ChromiumPageEvents) -> any ChromiumPageHandle {
        CEFPage(storageKey: storageKey, persistent: persistent, passkeys: passkeys, events: events)
    }

    func removeData(storageKey: String, persistent: Bool) async {
        await withCheckedContinuation { done in
            NRAChromiumPage.removeData(forStorageKey: storageKey, persistent: persistent) { done.resume() }
        }
    }

    func setCookies(_ cookies: [ChromiumCookie], storageKey: String, persistent: Bool) async -> Int {
        let items: [[String: Any]] = cookies.map { cookie in
            var item: [String: Any] = [
                "domain": cookie.domain, "name": cookie.name, "value": cookie.value, "path": cookie.path,
                "secure": cookie.isSecure, "httpOnly": cookie.isHTTPOnly,
            ]
            if let expires = cookie.expires { item["expires"] = expires.timeIntervalSince1970 }
            if let sameSite = cookie.sameSite { item["sameSite"] = sameSite }
            return item
        }
        return await withCheckedContinuation { done in
            NRAChromiumPage.setCookies(items, forStorageKey: storageKey, persistent: persistent) { done.resume(returning: $0) }
        }
    }

    func cookies(forSite site: String, storageKey: String, persistent: Bool) async -> [ChromiumCookie] {
        await withCheckedContinuation { done in
            NRAChromiumPage.cookies(forSite: site, storageKey: storageKey, persistent: persistent) { items in
                done.resume(returning: items.compactMap(Self.cookie(from:)))
            }
        }
    }

    /// A cookie from the bridge's dictionary form.
    nonisolated private static func cookie(from item: [String: Any]) -> ChromiumCookie? {
        guard let domain = item["domain"] as? String, let name = item["name"] as? String, let value = item["value"] as? String
        else { return nil }
        return ChromiumCookie(
            domain: domain, name: name, value: value, path: item["path"] as? String ?? "/",
            expires: (item["expires"] as? Double).map(Date.init(timeIntervalSince1970:)),
            isSecure: item["secure"] as? Bool ?? false, isHTTPOnly: item["httpOnly"] as? Bool ?? false,
            sameSite: item["sameSite"] as? String)
    }
}

/// One browser: forwards ChromiumPageHandle calls to the bridge and bridge callbacks to the adapter.
@MainActor
final class CEFPage: NSObject, ChromiumPageHandle {
    private weak var events: (any ChromiumPageEvents)?
    // Created right after super.init (the bridge needs `self` as its delegate) and never changed.
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var bridge: NRAChromiumPage!

    init(storageKey: String, persistent: Bool, passkeys: Bool, events: any ChromiumPageEvents) {
        self.events = events
        super.init()
        bridge = NRAChromiumPage(storageKey: storageKey, persistent: persistent, passkeys: passkeys, delegate: self)
    }

    var view: NSView { bridge.view }
    func load(_ url: String) { bridge.loadURL(url) }
    func goBack() { bridge.goBack() }
    func goForward() { bridge.goForward() }
    func reload() { bridge.reload() }
    func stop() { bridge.stop() }
    func exitFullscreen() { bridge.exitFullscreen() }
    func setZoomFactor(_ factor: Double) { bridge.setZoomFactor(factor) }
    func setMuted(_ muted: Bool) { bridge.setMuted(muted) }
    func find(_ text: String, forward: Bool, matchCase: Bool, findNext: Bool) {
        bridge.find(text, forward: forward, matchCase: matchCase, findNext: findNext)
    }
    func stopFinding() { bridge.stopFinding() }
    func startDownload(_ url: String) { bridge.startDownload(url) }
    func cancelDownload(_ id: UInt32) { bridge.cancelDownload(id) }
    func setDevToolsEnabled(_ enabled: Bool) { bridge.setDevToolsEnabled(enabled) }
    func showDevTools() { bridge.showDevTools() }
    func evaluate(_ script: String) async -> String? {
        await withCheckedContinuation { done in bridge.evaluate(script) { done.resume(returning: $0) } }
    }
    func close() {
        events = nil
        bridge.close()
    }
}

// Bridge callbacks arrive on the main thread (CEF's UI thread is the AppKit main thread).
extension CEFPage: @preconcurrency NRAChromiumPageDelegate {
    func chromiumPage(_ page: NRAChromiumPage, shouldNavigateTo url: String, mainFrame: Bool, trigger: NRANavigationTrigger) -> Bool {
        let mapped: ChromiumNavigationTrigger =
            switch trigger {
            case .userTyped: .userTyped
            case .linkClick: .linkClick
            case .redirect: .redirect
            default: .script
            }
        return events?.shouldNavigate(to: url, mainFrame: mainFrame, trigger: mapped) ?? false
    }

    func chromiumPage(_ page: NRAChromiumPage, didCommitURL url: String) { events?.didCommit(url: url) }

    func chromiumPage(_ page: NRAChromiumPage, didFinishURL url: String, httpStatus: Int32) {
        events?.didFinish(url: url, httpStatus: Int(httpStatus))
    }

    func chromiumPage(_ page: NRAChromiumPage, didFailURL url: String, code: Int32, text: String) {
        events?.didFail(url: url, code: Int(code), description: text)
    }

    func chromiumPage(_ page: NRAChromiumPage, titleChanged title: String) { events?.titleChanged(title) }
    func chromiumPage(_ page: NRAChromiumPage, fullscreen: Bool) { events?.fullscreenChanged(fullscreen) }
    func chromiumPage(_ page: NRAChromiumPage, favicon png: Data) { events?.faviconChanged(png) }
    func chromiumPage(
        _ page: NRAChromiumPage, webAuthn kind: String, json: String, frameURL: String, topURL: String,
        reply: @escaping (Bool, String) -> Void
    ) {
        guard let events else { return reply(false, "NotAllowedError|The page is closing.") }
        events.webAuthnRequested(kind: kind, json: json, frameURL: frameURL, topURL: topURL) { ok, payload in reply(ok, payload) }
    }

    func chromiumPage(_ page: NRAChromiumPage, loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        events?.loadingChanged(isLoading: loading, canGoBack: canGoBack, canGoForward: canGoForward)
    }

    func chromiumPage(_ page: NRAChromiumPage, progress: Double) { events?.progressChanged(progress) }

    func chromiumPage(
        _ page: NRAChromiumPage, dialog kind: NRADialogKind, originURL: String, message: String, defaultText: String,
        reply: @escaping (Bool, String?) -> Void
    ) {
        guard let events else { return reply(false, nil) }
        let mapped: ChromiumDialogKind =
            switch kind {
            case .alert: .alert
            case .confirm: .confirm
            default: .prompt
            }
        events.dialog(kind: mapped, originURL: originURL, message: message, defaultText: defaultText) { reply($0, $1) }
    }

    func chromiumPage(
        _ page: NRAChromiumPage, permissionRequestFromOrigin origin: String, kinds: NRAPermissionKinds,
        reply: @escaping (Bool) -> Void
    ) {
        guard let events else { return reply(false) }
        var mapped: Set<ChromiumPermissionKind> = []
        if kinds.contains(.camera) { mapped.insert(.camera) }
        if kinds.contains(.microphone) { mapped.insert(.microphone) }
        if kinds.contains(.location) { mapped.insert(.location) }
        if kinds.contains(.notifications) { mapped.insert(.notifications) }
        if kinds.contains(.clipboardRead) { mapped.insert(.clipboardRead) }
        events.permissionRequested(origin: origin, kinds: mapped) { reply($0) }
    }

    func chromiumPage(
        _ page: NRAChromiumPage, downloadRequested downloadID: UInt32, url: String, suggestedName: String, mimeType: String,
        totalBytes: Int64, reply: @escaping (String?) -> Void
    ) {
        guard let events else { return reply(nil) }
        let info = ChromiumDownloadInfo(id: downloadID, url: url, suggestedName: suggestedName, mimeType: mimeType, totalBytes: totalBytes)
        events.downloadRequested(info) { reply($0) }
    }

    func chromiumPage(
        _ page: NRAChromiumPage, download downloadID: UInt32, received: Int64, total: Int64, complete: Bool, canceled: Bool,
        interrupted: Bool, path: String
    ) {
        events?.downloadUpdated(
            ChromiumDownloadProgress(
                id: downloadID, received: received, total: total, isComplete: complete, isCanceled: canceled,
                isInterrupted: interrupted, path: path))
    }

    func chromiumPage(_ page: NRAChromiumPage, findMatches matches: Int32, active: Int32, isFinal: Bool) {
        events?.findMatches(Int(matches), active: Int(active), isFinal: isFinal)
    }

    func chromiumPage(_ page: NRAChromiumPage, processTerminated reason: NRATermination) {
        let mapped: ChromiumTermination =
            switch reason {
            case .crashed: .crashed
            case .killed: .killed
            case .outOfMemory: .outOfMemory
            default: .other
            }
        events?.processTerminated(mapped)
    }
}
