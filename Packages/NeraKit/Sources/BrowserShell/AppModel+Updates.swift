// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Update

#if os(macOS)
    import AppKit
#endif

/// Where an update stands.
public enum UpdateStatus: Equatable, Sendable {
    /// Nothing to do.
    case idle
    /// A newer version is downloading and being checked.
    case preparing(version: String)
    /// A verified newer version is staged: it's installed on the next quit, or now with "Restart to Update".
    case ready(version: String)
}

// Updates (ADR-0011): once a day Nera reads its signed feed, downloads the newer build, checks its Ed25519
// signature and its Developer ID signature, and stages it next to the app. It's swapped in when Nera quits, or at
// once with "Restart to Update". Builds without a feed, a key or a Developer ID (development builds) fall back to
// telling the user about a newer GitHub release.
extension AppModel {
    static let updateCheckKey = "NeraCheckForUpdates"
    static let lastUpdateCheckKey = "NeraLastUpdateCheck"
    static let rolloutGroupKey = "NeraUpdateRolloutGroup"

    /// Whether Nera checks for new versions (on by default; Settings › General).
    public var checksForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Self.updateCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.updateCheckKey) }
    }

    /// This build's version (CFBundleShortVersionString).
    public var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }

    /// This build's number (CFBundleVersion).
    public var appBuild: Int { (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0 }

    /// The checker for this build, if it has a feed and an update key (release builds). A check the user asked for
    /// (Check for Updates…) skips the staged rollout, as Sparkle does: they get the newest version now.
    func updateChecker(manual: Bool = false) -> UpdateChecker? {
        let info = Bundle.main.infoDictionary ?? [:]
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.rolloutGroupKey) == nil { defaults.set(Int.random(in: 0..<7), forKey: Self.rolloutGroupKey) }
        return UpdateChecker(
            feedURL: (info["NeraUpdateFeedURL"] as? String).flatMap(URL.init(string:)),
            publicKeyBase64: info["NeraUpdatePublicKey"] as? String, currentBuild: appBuild, channel: .stable,
            rolloutGroup: manual ? 0 : defaults.integer(forKey: Self.rolloutGroupKey))
    }

    /// Checks at most once a day (or now when `force`), and gets a newer version ready to install.
    public func checkForUpdates(force: Bool = false) {
        guard force || checksForUpdates, updateStatus == .idle || force else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastUpdateCheckKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckKey)
        #if os(macOS)
            if let checker = updateChecker(manual: force), let installer = UpdateInstaller() {
                Task { await prepareUpdate(checker: checker, installer: installer, force: force) }
                return
            }
        #endif
        checkGitHubRelease(force: force)
    }

    #if os(macOS)
        /// Finds, downloads, verifies and stages the update.
        private func prepareUpdate(checker: UpdateChecker, installer: UpdateInstaller, force: Bool) async {
            if case .ready = updateStatus { return }
            guard let item = try? await checker.check() else {
                if force { notice = "Nera \(appVersion) is the latest version." }
                return
            }
            updateStatus = .preparing(version: item.displayVersion)
            do {
                let data = try await checker.download(item)
                let staged: URL = try await Task.detached {
                    let file = FileManager.default.temporaryDirectory.appending(path: "Nera-update-\(item.build).dmg")
                    try data.write(to: file, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: file) }
                    return try installer.stage(diskImage: file, expectedBuild: item.build)
                }.value
                _ = staged
                updateStatus = .ready(version: item.displayVersion)
            } catch UpdateInstaller.Failure.notWritable {
                // Nera's folder can't be written: offer the download instead.
                updateStatus = .idle
                availableUpdate = (item.displayVersion, item.url)
            } catch {
                updateStatus = .idle
                if force { notice = "Nera \(item.displayVersion) couldn't be downloaded. Try again later." }
            }
        }

        /// Quits and reopens Nera on the new version.
        public func restartToUpdate() {
            guard case .ready = updateStatus, let installer = UpdateInstaller() else { return }
            do {
                try installer.installWhenQuit(relaunch: true)
                store.flush()
                NSApp.terminate(nil)
            } catch {
                updateStatus = .idle
                notice = "The update couldn't be installed. It will be downloaded again."
            }
        }

        /// Called as Nera quits: a ready update takes its place (without reopening).
        public func installPendingUpdateOnQuit() {
            guard case .ready = updateStatus, let installer = UpdateInstaller() else { return }
            try? installer.installWhenQuit(relaunch: false)
        }
    #endif

    /// Development builds: tell the user about a newer GitHub release.
    private func checkGitHubRelease(force: Bool) {
        let current = appVersion
        Task { [weak self] in
            let release = await ReleaseCheck.newerRelease(than: current)
            guard let self else { return }
            if let release {
                availableUpdate = (release.version, release.url)
            } else if force {
                notice = "Nera \(current) is the latest version."
            }
        }
    }

    /// Opens the release page of the available update.
    public func downloadUpdate() {
        guard let update = availableUpdate else { return }
        send(.tab(.open(update.url, .newTab)))
        availableUpdate = nil
    }
}
