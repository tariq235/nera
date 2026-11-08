// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import EngineKit
public import Foundation
public import Import
import Storage

#if os(macOS)
    import AppKit
    public import BrowserData
#endif

/// What a welcome-screen import brought in, for the summary step.
public struct ImportSummary: Equatable, Sendable {
    /// Spaces added.
    public var spaces = 0
    /// Tabs added (pinned, Today, in folders and splits).
    public var tabs = 0
    /// Folders added.
    public var folders = 0
    /// Favorites added.
    public var favorites = 0
    /// Archived tabs kept.
    public var archived = 0
    /// Bookmarks added.
    public var bookmarks = 0
    /// History pages added.
    public var history = 0
    /// Site icons added.
    public var icons = 0
    /// Websites the user stays signed in to (their sign-in cookies came over).
    public var signIns = 0
    /// What couldn't be read.
    public var problems: [String] = []
}

// The welcome screen's imports and the + New Space flow.
extension AppModel {
    /// The extension Nera installs for "Block ads and trackers": uBlock Origin Lite (Manifest V3, GPL-3.0).
    public static let blockerExtensionID = "ddkjiahejlhfcafbddmgiahcphecmpfh"

    /// Whether the tracker blocker is installed.
    public var hasBlocker: Bool { extensionStore.extensions.contains { $0.id == Self.blockerExtensionID } }

    /// Installs Web Store extensions one by one. Returns how many installed. They start after a relaunch.
    public func installFromWebStore(_ ids: [String]) async -> Int {
        var installed = 0
        if extensionStore.profileID == nil { extensionStore.profileID = extensionsProfileID }
        for id in ids where !extensionStore.extensions.contains(where: { $0.id == id }) {
            if (try? await extensionStore.installFromWebStore(id, chromiumMajor: chromiumMajor)) != nil { installed += 1 }
        }
        if installed > 0 {
            extensionsRevision += 1
            needsRelaunchForExtensions = true
        }
        return installed
    }

    #if os(macOS)
        /// Arc's Spaces, Favorites and archived tabs on this Mac, for the welcome screen to preview. Nothing is
        /// changed until ``importArc(_:spaces:archive:history:)``.
        public func previewArc() -> (library: ArcImporter.Result, archive: [ArchivedTab])? {
            guard let profileID = state.currentProfile?.id,
                let data = try? Data(contentsOf: ArcImporter.defaultSidebarURL),  // naming: import-reference
                let result = try? ArcImporter.parse(data: data, profileID: profileID)
            else { return nil }
            let archive = (try? Data(contentsOf: ArcImporter.defaultArchiveURL)).map { ArcImporter.parseArchive(data: $0) } ?? []
            // Site icons first, so the preview (and the sidebar later) show real icons. Only Nera's icon cache changes.
            let tabs = result.favorites + result.spaces.flatMap { ($0.pinned + $0.today).flatMap(\.tabs) }
            importIcons(.arc, tabs: tabs)  // naming: import-reference
            return (result, archive)
        }

        /// Imports the picked Arc Spaces with the Favorites, and optionally their archived tabs and Arc's
        /// bookmarks and history. The empty starter Space is removed.
        public func importArc(
            _ preview: (library: ArcImporter.Result, archive: [ArchivedTab]), spaces picked: Set<UUID>, archive: Bool, history: Bool
        ) -> ImportSummary {
            let starter = state.spaces.count == 1 && (state.spaces[0].pinned + state.spaces[0].today).isEmpty ? state.spaces.first : nil
            let spaces = preview.library.spaces.filter { picked.contains($0.id) }
            var summary = ImportSummary()
            summary.spaces = spaces.count
            summary.tabs = spaces.flatMap { $0.pinned + $0.today }.flatMap(\.tabs).count
            summary.folders = spaces.flatMap { $0.pinned + $0.today }.filter(\.isFolder).count
            summary.favorites = preview.library.favorites.count
            send(.library(.importLibrary(spaces: spaces, favorites: preview.library.favorites)))
            if let starter, !spaces.isEmpty { send(.space(.delete(starter.id))) }
            if archive {
                let ids = Set(spaces.map(\.id))
                let tabs = preview.archive.filter { ids.contains($0.spaceID) }
                send(.library(.importArchive(tabs)))
                summary.archived = min(tabs.count, BrowserState.archiveLimit)
            }
            let data = importBrowserData(.arc, bookmarks: history, history: history)  // naming: import-reference
            summary.bookmarks = data.bookmarks
            summary.history = data.history
            let hosts = Set(
                (spaces.flatMap { ($0.pinned + $0.today).flatMap(\.tabs) } + preview.library.favorites).compactMap { $0.url?.host() })
            summary.icons = hosts.filter { favicons.icon(forHost: $0) != nil }.count
            summary.problems = data.problems
            if let first = state.spaces.first { send(.space(.select(first.id))) }
            return summary
        }

        /// Imports bookmarks, history and site icons from another browser. When the profile has no Favorites
        /// yet, the most visited sites become Favorites.
        public func importOtherBrowser(_ source: ImportSource, files: [URL] = []) -> ImportSummary {
            var summary = importBrowserData(source, bookmarks: true, history: true, files: files)
            if let profile = state.currentProfile, profile.favorites.isEmpty {
                let top = (history?.topSites(profileID: profile.id, limit: 8) ?? [])
                    .compactMap { entry in entry.url.host().map { _ in entry } }
                    .map { Tab(id: UUID(), url: $0.url, title: $0.title, homeURL: $0.url, lastActiveAt: Date()) }
                if !top.isEmpty { send(.library(.importLibrary(spaces: [], favorites: top))) }
                summary.favorites = top.count
            }
            return summary
        }

        /// Brings website sign-ins (cookies) over from a Chromium-family browser into the current profile, so the
        /// user stays signed in. macOS asks the user first (the browser's key is in the Keychain). Returns how many
        /// websites came over, or `nil` when access wasn't allowed. Cookie values never leave memory or get logged.
        public func importSignIns(from source: ImportSource) async -> Int? {
            guard !isPrivate, let profile = state.currentProfile, ChromiumCookies.keychainItem(for: source) != nil else { return nil }
            let read = await Task.detached { try? ChromiumCookies.read(from: source) }.value
            guard let cookies = read else { return nil }
            let web = cookies.map {
                WebCookie(
                    domain: $0.domain, name: $0.name, value: $0.value, path: $0.path, expires: $0.expires, isSecure: $0.isSecure,
                    isHTTPOnly: $0.isHTTPOnly, sameSite: $0.sameSite)
            }
            let engine = pages.registry.engine(for: profile)
            // Every engine gets the sign-ins: sites shown with WebKit (streaming, video) stay signed in too.
            let others = pages.registry.availableEngines.filter { $0.descriptor.id != engine.descriptor.id }
            for other in others { Task { _ = await other.addCookies(web.filter(Self.isStorable), to: profile.id) } }
            if chromiumWaitsForWelcome() {
                // Chromium starts when the welcome finishes: the cookies wait for it, so don't wait on them here (the
                // welcome itself is what lets Chromium start). Kept until then in case Chromium can't start. Only
                // cookies Chromium will accept are counted, since it can't confirm them yet.
                let accepted = web.filter(Self.isStorable)
                pendingSignIns = (profile.id, accepted)
                Task { _ = await engine.addCookies(accepted, to: profile.id) }
                return Set(accepted.map { Self.site(of: $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain) }).count
            }
            guard await engine.addCookies(web, to: profile.id) > 0 else { return 0 }
            return Set(cookies.map { Self.site(of: $0.host) }).count
        }

        /// A cookie a browser will store: a name, a host-like domain, and Secure when SameSite=None.
        static func isStorable(_ cookie: WebCookie) -> Bool {
            let host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard !cookie.name.isEmpty, !host.isEmpty, host.contains("."), !host.contains(" ") else { return false }
            return cookie.sameSite != "None" || cookie.isSecure
        }

        /// Follows Chromium's start after the welcome: once it's running, the imported cookie values are dropped
        /// from memory; if it can't start, Nera continues on WebKit, which gets the imported sign-ins, and pages made
        /// during the welcome are made again on WebKit.
        func followChromiumStartup() {
            let center = NotificationCenter.default
            center.addObserver(forName: ChromiumStartup.didStart, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pendingSignIns = nil }
            }
            center.addObserver(forName: ChromiumStartup.didFail, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.chromiumDidFail() }
            }
        }

        /// Chromium couldn't start: WebKit takes over.
        func chromiumDidFail() {
            pages.discardAll()  // pages made while Chromium was pending are made again, on WebKit, when shown
            guard let pending = pendingSignIns else { return }
            pendingSignIns = nil
            let webKit = pages.registry.availableEngines.first { $0.descriptor.id == "webkit" }
            Task { _ = await webKit?.addCookies(pending.cookies, to: pending.profileID) }
        }

        /// The registrable part of a host, roughly ("mail.google.com" → "google.com"), for counting websites.
        static func site(of host: String) -> String { SiteEngines.registrableDomain(host) }

        /// Reads bookmarks, history and icons from `source` into the current profile.
        func importBrowserData(
            _ source: ImportSource, bookmarks: Bool, history wantsHistory: Bool, files: [URL] = []
        ) -> ImportSummary {
            guard let profile = state.currentProfile else { return ImportSummary() }
            var problems: [String] = []
            var tree: [Bookmark] = []
            var visits: [ImportedVisit] = []
            do {
                if bookmarks { tree = try Self.readBookmarks(source, files: files) }
            } catch {
                problems.append("Bookmarks")
            }
            do {
                if wantsHistory { visits = try Self.readHistory(source, files: files) }
            } catch {
                problems.append("History")
            }
            if !tree.isEmpty {
                send(.library(.bookmarks(profileID: profile.id, .importTree(tree, folderTitle: "Imported from \(source.displayName)"))))
            }
            let entries = visits.map { HistoryEntry(url: $0.url, title: $0.title, lastVisit: $0.lastVisit, visitCount: $0.visitCount) }
            let added = history?.importVisits(entries, profileID: profile.id) ?? 0
            historyDidChange()
            let icons = importIcons(source, tabs: [])
            return ImportSummary(bookmarks: tree.allLinks.count, history: added, icons: icons, problems: problems)
        }

        /// Copies site icons from another browser into Nera's icon cache (hosts that have none yet). For Arc,
        /// its sidebar icon cache covers the `tabs` being imported. Returns how many were added.
        @discardableResult func importIcons(_ source: ImportSource, tabs: [BrowserCore.Tab]) -> Int {
            var found: [String: Data] = [:]
            if source == .arc {  // naming: import-reference
                found = ArcImporter.sidebarIcons(for: tabs, cache: ArcImporter.defaultIconCacheURL)
            }
            if source.isChromium, let file = source.dataDirectory?.appending(path: "Favicons"),
                let more = try? BrowserImport.chromiumFavicons(at: file)
            {
                found.merge(more) { first, _ in first }
            }
            var added = 0
            for (host, png) in found where favicons.icon(forHost: host) == nil {
                favicons.save(png, forHost: host)
                added += 1
            }
            return added
        }

        /// Tabs brought over from Arc keep Arc's IDs, so Arc's sidebar icon cache can fill in icons that are
        /// still missing (for example after an import made before Nera read that cache). Reads local files only.
        public func fillMissingIconsFromArc() {
            guard isArcInstalled, !isPrivate else { return }
            let tabs = state.profiles.flatMap(\.favorites) + state.spaces.flatMap { ($0.pinned + $0.today).flatMap(\.tabs) }
            let missing = tabs.filter { tab in tab.url?.host().map { favicons.icon(forHost: $0) == nil } ?? false }
            guard !missing.isEmpty else { return }
            importIcons(.arc, tabs: missing)  // naming: import-reference
        }

        /// Site icons from every Chromium browser on this Mac, so suggested sites show their real icons on a
        /// fresh install. Reads local files only; fills in hosts that have no icon yet. Returns how many were added.
        public func borrowIconsFromInstalledBrowsers() -> Int {
            ImportSource.allCases.filter { $0.isChromium && $0.isInstalled }.reduce(0) { $0 + importIcons($1, tabs: []) }
        }

        /// Web Store extensions in `source`'s profile (Chromium browsers only).
        public func extensionsIn(_ source: ImportSource) -> [FoundExtension] {
            guard source.isChromium, supportsExtensions, let dir = source.dataDirectory else { return [] }
            return BrowserExtensions.list(inProfile: dir).filter { $0.id != Self.blockerExtensionID }
        }
    #endif

    /// + New Space: makes a Space and opens Edit Space to name and style it. Cancel removes it again.
    public func newSpace() {
        let before = Set(state.spaces.map(\.id))
        send(.space(.create(title: "")))
        guard let id = state.spaces.first(where: { !before.contains($0.id) })?.id else { return }
        let n = state.spaces.count
        let look = SpaceTheme.swatches[(n * 5) % SpaceTheme.swatches.count]
        send(.space(.customize(id, icon: .emoji(EditSpaceView.emojis[(n * 7) % EditSpaceView.emojis.count]), theme: look)))
        isCreatingSpace = true
        editingSpaceID = id
    }

    /// Closes Edit Space. When it was naming a new Space, `keep: false` removes the Space.
    public func endEditingSpace(keep: Bool) {
        if isCreatingSpace, let id = editingSpaceID {
            if !keep {
                send(.space(.delete(id)))
            } else if let space = state.spaces.first(where: { $0.id == id }), space.title.trimmingCharacters(in: .whitespaces).isEmpty {
                send(.space(.rename(id, title: "Space \(state.spaces.count)")))
            }
        }
        isCreatingSpace = false
        editingSpaceID = nil
    }
}
