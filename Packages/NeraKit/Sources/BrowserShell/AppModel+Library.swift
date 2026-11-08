// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import BrowserData
import CommandBar
public import Foundation
import Import
import SecurityPolicy
import Storage

// Profiles, bookmarks, browser import and history: the library features of the app model.
extension AppModel {
    // MARK: Profiles

    /// Engines a profile can use on this device: (id, name), platform default first.
    public var selectableEngines: [(id: EngineID, name: String)] {
        pages.registry.availableEngines.map { (EngineID(rawValue: $0.descriptor.id), $0.descriptor.displayName) }
    }

    /// Spaces using a profile.
    public func spaceCount(for profileID: UUID) -> Int { state.spaces.filter { $0.profileID == profileID }.count }

    // MARK: Bookmarks

    /// Sends a bookmark change for the current profile.
    public func bookmarks(_ action: BookmarkAction) {
        guard let profile = state.currentProfile else { return }
        send(.library(.bookmarks(profileID: profile.id, action)))
    }

    /// The current page's bookmark, if it has one (top level or any folder).
    public var currentPageBookmark: Bookmark? {
        guard let url = state.selectedTab?.url else { return nil }
        return state.currentProfile?.bookmarkTree.allLinks.first { $0.url == url }
    }

    /// ⇧⌘D: bookmarks the current page, or removes its bookmark.
    public func toggleBookmarkForCurrentPage() {
        if let existing = currentPageBookmark { return bookmarks(.delete(existing.id)) }
        guard let tab = state.selectedTab, let url = tab.url, HistoryStore.isRecordable(url) else { return }
        bookmarks(.add(title: tab.displayTitle, url: url, folderID: nil))
        notice = "Bookmarked “\(tab.displayTitle)”."
    }

    /// Writes the current profile's bookmarks as a bookmarks HTML file.
    public func exportBookmarks(to file: URL) {
        let html = BookmarksHTML.export(state.currentProfile?.bookmarkTree ?? [])
        do {
            try Data(html.utf8).write(to: file, options: .atomic)
            notice = "Exported \(state.currentProfile?.bookmarkTree.allLinks.count ?? 0) bookmarks."
        } catch {
            notice = "Couldn't save the bookmarks file."
        }
    }

    #if os(macOS)
        /// Imports bookmarks and/or history into the current profile. `files` are user-picked files (Safari, or a
        /// bookmarks HTML file); for other browsers Nera reads their default profile directly.
        public func importFromBrowser(
            _ source: ImportSource, bookmarks importBookmarks: Bool, history importHistory: Bool, files: [URL] = []
        ) {
            let result = importBrowserData(source, bookmarks: importBookmarks, history: importHistory, files: files)
            isBrowserImportPresented = false
            var summary = "Imported \(result.bookmarks) bookmarks and \(result.history) history pages from \(source.displayName)."
            if !result.problems.isEmpty {
                summary +=
                    " Some data was skipped: " + result.problems.map { "\($0.lowercased()) couldn't be read" }.joined(separator: ", ")
                summary += source == .safari ? " (choose Safari's files, or give Nera Full Disk Access)." : "."
            }
            notice = summary
        }

        static func readBookmarks(_ source: ImportSource, files: [URL]) throws -> [Bookmark] {
            switch source {
            case .bookmarksFile:
                guard let f = files.first else { return [] }
                return try BookmarksHTML.parse(String(decoding: try Data(contentsOf: f), as: UTF8.self))
            case .safari:
                guard let f = files.first(where: { $0.lastPathComponent == "Bookmarks.plist" }) ?? source.bookmarksFile else { return [] }
                return try BrowserImport.safariBookmarks(Data(contentsOf: f))
            case .firefox:
                guard let f = source.bookmarksFile else { return [] }
                return try BrowserImport.firefoxBookmarks(at: f)
            default:
                guard let f = source.bookmarksFile, FileManager.default.fileExists(atPath: f.path) else { return [] }
                return try BrowserImport.chromiumBookmarks(Data(contentsOf: f))
            }
        }

        static func readHistory(_ source: ImportSource, files: [URL]) throws -> [ImportedVisit] {
            switch source {
            case .bookmarksFile: return []
            case .safari:
                guard let f = files.first(where: { $0.lastPathComponent == "History.db" }) ?? source.historyFile else { return [] }
                return try BrowserImport.safariHistory(at: f)
            case .firefox: return try source.historyFile.map(BrowserImport.firefoxHistory(at:)) ?? []
            default: return try source.historyFile.map(BrowserImport.chromiumHistory(at:)) ?? []
            }
        }
    #endif

    // MARK: History

    /// Opens a history entry in a new tab.
    public func openFromHistory(_ url: URL) {
        isHistoryPresented = false
        send(.tab(.open(url, .newTab)))
    }

    /// Removes one page from the current profile's history.
    public func deleteFromHistory(_ url: URL) {
        guard let profile = state.currentProfile else { return }
        history?.delete(url, profileID: profile.id)
        historyDidChange()
    }

    /// Clear Browsing Data: history from `since` (or all of it), and optionally every cookie, site data and
    /// cache of the current profile (which signs the user out of websites).
    public func clearBrowsingData(since: Date?, history: Bool, siteData: Bool) {
        guard !isPrivate, let profile = state.currentProfile else { return }
        if history { clearHistory(since: since) }
        if siteData {
            let engines = pages.registry.engines
            Task { @MainActor in
                for engine in engines { await engine.removeWebsiteData(for: .persistent(profile.id)) }
                self.reload()
            }
        }
        notice = siteData ? "Browsing data cleared. You may need to sign in to websites again." : "History cleared."
    }

    /// Clears the current profile's history since a date (all of it when nil).
    public func clearHistory(since: Date?) {
        guard let profile = state.currentProfile else { return }
        history?.clear(profileID: profile.id, since: since)
        historyDidChange()
    }

    // MARK: Sidebar and command bar lookups

    /// The tab's icon: its live page's favicon, else the cached one for its host.
    public func favicon(for tab: BrowserCore.Tab) -> Data? {
        if let live = pages.existingPage(for: tab.id)?.state.favicon { return live }
        return tab.url?.host().flatMap(favicons.icon(forHost:))
    }
}
