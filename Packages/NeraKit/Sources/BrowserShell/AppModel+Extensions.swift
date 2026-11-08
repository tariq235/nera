// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import BrowserData
public import EngineKit
public import Extensions
public import Foundation
import SecurityPolicy
import Storage

#if os(macOS)
    import AppKit
#endif

/// What Chromium needs at start: the enabled extension folders and the profile they run in. Read by the app's
/// Chromium bootstrap before the engine starts, so it can't come from the (later) app model.
public enum ExtensionStartup {
    /// Enabled extensions and their profile; nothing in automated test runs.
    public static func configuration() -> (paths: [String], profile: UUID?) {
        #if DEBUG
            if ProcessInfo.processInfo.environment["NERA_UI_TEST"] != nil || CommandLine.arguments.contains("--engine-self-test") {
                return ([], nil)
            }
        #endif
        let store = ExtensionStore.standard()
        return (store.enabledPaths, store.profileID ?? mainProfileID)  // the main profile, extensions or not
    }
}

/// When Chromium starts. Normally at launch; on a first launch, when the welcome finishes, so the extensions it
/// installs (the blocker, imported ones) load on that first start and no restart is needed. Until then Chromium counts
/// as available and pages and imported sign-ins wait for it (NRAChromium.whenStarted).
public enum ChromiumStartup {
    /// The welcome shows on this launch (set when the library loads, before Chromium would start).
    nonisolated(unsafe) public static var welcomeOnThisLaunch = false
    /// Chromium is enabled and waits for the welcome to finish. Set by the app when it schedules Chromium, cleared
    /// only once Chromium has started (or failed), so there's never a moment when pages fall back to WebKit.
    nonisolated(unsafe) public static var waitsForWelcome = false
    /// Posted when the welcome finishes and Chromium may start.
    public static let welcomeFinished = Notification.Name("NeraChromiumMayStart")
    /// Posted when Chromium started after the welcome.
    public static let didStart = Notification.Name("NeraChromiumDidStart")
    /// Posted when Chromium couldn't start: Nera continues with WebKit.
    public static let didFail = Notification.Name("NeraChromiumDidFailToStart")
}

extension ExtensionStartup {
    /// Nera's main profile, known once the library loads (before Chromium starts): it's always Chromium's startup
    /// profile, so its data stays in one folder whether or not extensions are installed.
    nonisolated(unsafe) public static var mainProfileID: UUID?

    /// Moves the main profile's data stranded by builds up to 8 into the folder Chromium reads (before it starts).
    @discardableResult
    public static func repairMainProfile(chromiumRoot: URL, profileID: UUID) -> ChromiumProfileRepair.Outcome {
        ChromiumProfileRepair.repair(root: chromiumRoot, profileID: profileID)
    }

    /// Mirrors allowlisted password-manager native-messaging hosts (iCloud Passwords, 1Password, Bitwarden) into
    /// Chromium's data folder, so their extensions can reach their apps (FEAT-027). Not in automated test runs.
    public static func prepareNativeMessagingHosts(chromiumRoot: URL) {
        #if DEBUG
            if ProcessInfo.processInfo.environment["NERA_UI_TEST"] != nil || CommandLine.arguments.contains("--engine-self-test") {
                return
            }
        #endif
        NativeMessagingHosts.mirror(into: chromiumRoot.appending(path: "NativeMessagingHosts"))
    }
}

// Chrome extensions (FEAT-029; ADR-0012).
extension AppModel {
    /// Whether this Nera can run Chrome extensions (the Chromium engine is available).
    public var supportsExtensions: Bool {
        pages.registry.availableEngines.contains { $0.capabilities.contains(.extensions) }
    }

    /// The profile extensions run in (its pages only; ADR-0012).
    public var extensionsProfileID: UUID? { extensionStore.profileID ?? state.profiles.first?.id }

    /// Chromium's major version, for Web Store downloads.
    var chromiumMajor: Int {
        let version = pages.registry.availableEngines.first { $0.capabilities.contains(.extensions) }?.descriptor.version ?? ""
        return version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first { $0 > 100 } ?? 156
    }

    /// Installs from a Chrome Web Store link or ID. Takes effect after a relaunch.
    public func installExtension(fromWebStore input: String) async {
        do {
            if extensionStore.profileID == nil { extensionStore.profileID = extensionsProfileID }
            let ext = try await extensionStore.installFromWebStore(input, chromiumMajor: chromiumMajor)
            extensionsChanged(notice: "Installed \(ext.name). Relaunch Nera to start it.")
        } catch {
            notice = Self.describe(error)
        }
    }

    /// Installs a CRX file the user picked (must be validly signed by its developer).
    public func installExtension(fromFile url: URL) {
        do {
            if extensionStore.profileID == nil { extensionStore.profileID = extensionsProfileID }
            let ext = try extensionStore.install(crx: Data(contentsOf: url), from: .file)
            extensionsChanged(notice: "Installed \(ext.name). Relaunch Nera to start it.")
        } catch {
            notice = Self.describe(error)
        }
    }

    /// Turns an extension on or off (after a relaunch).
    public func setExtension(_ id: String, enabled: Bool) {
        extensionStore.setEnabled(id, enabled)
        extensionsChanged(notice: nil)
    }

    /// Removes an extension (stops after a relaunch).
    public func removeExtension(_ id: String) {
        extensionStore.remove(id)
        extensionsChanged(notice: nil)
    }

    /// Chooses the profile extensions run in (after a relaunch).
    public func setExtensionsProfile(_ id: UUID) {
        extensionStore.profileID = id
        extensionsChanged(notice: nil)
    }

    private func extensionsChanged(notice text: String?) {
        extensionsRevision += 1
        needsRelaunchForExtensions = true
        if let text { notice = text }
    }

    static func describe(_ error: any Error) -> String {
        switch error as? ExtensionInstallError {
        case .notAWebStoreLink?: "That isn't a Chrome Web Store link or extension ID."
        case .downloadFailed?: "The extension couldn't be downloaded. Check your connection and try again."
        case .unsupportedManifestVersion(let v)?: "This extension uses Manifest V\(v), which current Chromium no longer runs."
        case .invalidPackage(.notSignedByWebStore)?: "That package isn't signed by the Chrome Web Store."
        case .invalidPackage?: "That extension package isn't validly signed, so Nera won't install it."
        case .badManifest?, .unpackFailed?: "That extension package is damaged."
        case nil: "The extension couldn't be installed."
        }
    }

    /// Quits and reopens Nera (extensions load when Chromium starts).
    public func relaunch() {
        #if os(macOS)
            let path = Bundle.main.bundlePath
            let reopen = Process()
            reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
            reopen.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
            try? reopen.run()
            store.flush()
            NSApp.terminate(nil)
        #endif
    }

    /// A page showing an extension's toolbar popup, in the extensions profile. Only these pages may load
    /// `chrome-extension://` URLs (NavigationPolicy.allowsExtensionPages).
    public func makeExtensionPopup(_ ext: InstalledExtension, delegate: any WebPageDelegate) -> (any WebPage)? {
        guard let popup = ext.popupPath, let profile = extensionsProfileID,
            let engine = pages.registry.availableEngines.first(where: { $0.capabilities.contains(.extensions) }),
            let url = URL(string: "chrome-extension://\(ext.id)/\(popup)")
        else { return nil }
        var policy = pages.policy
        policy.allowsExtensionPages = true
        let page = engine.makePage(PageConfiguration(id: UUID(), storage: .persistent(profile), policy: policy), delegate: delegate)
        page.load(url)
        return page
    }
}
