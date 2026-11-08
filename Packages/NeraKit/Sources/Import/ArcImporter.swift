// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import CryptoKit
public import Foundation

/// Imports Spaces, pinned tabs, folders, today tabs and Favorites from Arc's `StorableSidebar.json`.
/// Parsed with JSONSerialization (not Codable) so
/// unknown or future item kinds are counted and skipped instead of failing the whole import.
public enum ArcImporter {
    /// What an import brought in, shown to the user afterwards.
    public struct Report: Equatable, Sendable {
        /// Spaces imported.
        public var spaces = 0
        /// Tabs imported (pinned, Today, in folders and splits).
        public var tabs = 0
        /// Folders imported.
        public var folders = 0
        /// Favorites imported.
        public var favorites = 0
        /// Item kinds we don't support yet (e.g. "easel"), with counts.
        public var skipped: [String: Int] = [:]
        /// Spaces that used a non-default Arc profile; imported into the target profile.
        public var spacesFromOtherProfiles = 0

        /// An empty report.
        public init() {}
    }

    /// The imported library pieces, ready for `LibraryAction.importLibrary`.
    public struct Result: Sendable {
        /// Imported Spaces, assigned to the target profile.
        public var spaces: [Space]
        /// Imported Favorites.
        public var favorites: [Tab]
        /// Counts for the user.
        public var report: Report

        /// Creates a result.
        public init(spaces: [Space], favorites: [Tab], report: Report = Report()) {
            self.spaces = spaces
            self.favorites = favorites
            self.report = report
        }
    }

    /// Why an import failed.
    public enum ImportError: Error, Equatable {
        /// The file isn't Arc's `StorableSidebar.json`.
        case notArcSidebarFile
    }

    #if os(macOS)
        /// Where Arc keeps the file on macOS. Nera reads it only when the user chooses Import from Arc.
        public static var defaultSidebarURL: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Arc/StorableSidebar.json")
        }
    #endif

    /// Parses an Arc `StorableSidebar.json`. Untrusted input: never traps; unknown item kinds are
    /// counted in ``Report/skipped`` and left out.
    /// - Parameters:
    ///   - data: The file's contents.
    ///   - profileID: The Nera profile the imported Spaces will use.
    ///   - uuid: Source of IDs for items whose Arc ID isn't a UUID.
    public static func parse(
        data: Data, profileID: UUID, uuid: () -> UUID = { UUID() }
    ) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sidebar = root["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [Any],
            let main = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil && $0["items"] != nil })
        else { throw ImportError.notArcSidebarFile }

        var report = Report()
        let items = Dictionary(keyedPairs(main["items"]), uniquingKeysWith: { a, _ in a })

        func id(_ raw: String) -> UUID { UUID(uuidString: raw) ?? uuid() }

        func children(of containerID: String) -> [String] {
            items[containerID]?["childrenIds"] as? [String] ?? []
        }

        func node(_ itemID: String, pinned: Bool) -> Node? {
            guard let item = items[itemID], let data = item["data"] as? [String: Any], let kind = data.keys.first else { return nil }
            let title = item["title"] as? String
            switch kind {
            case "tab":
                guard let tab = makeTab(item: item, data: data["tab"] as? [String: Any] ?? [:], id: id(itemID), pinned: pinned) else {
                    report.skipped["tab-without-url", default: 0] += 1
                    return nil
                }
                report.tabs += 1
                return .tab(tab)
            case "list":
                report.folders += 1
                let kids = (item["childrenIds"] as? [String] ?? []).compactMap { node($0, pinned: pinned) }
                return Node(id: id(itemID), kind: .folder(Folder(title: title ?? "Folder", children: kids, isExpanded: false)))
            case "splitView":
                let tabs = (item["childrenIds"] as? [String] ?? []).compactMap { node($0, pinned: pinned) }.flatMap(\.tabs)
                if tabs.count >= 2 { return Node(id: id(itemID), kind: .split(Split(tabs: tabs))) }
                return tabs.first.map(Node.tab)
            default:
                report.skipped[kind, default: 0] += 1
                return nil
            }
        }

        var spaces: [Space] = []
        for (spaceID, space) in keyedPairs(main["spaces"]) {
            var pinnedID: String?
            var unpinnedID: String?
            for (label, containerID) in labeledPairs(space["containerIDs"]) {
                if label == "pinned" { pinnedID = containerID } else if label == "unpinned" { unpinnedID = containerID }
            }
            if let profile = space["profile"] as? [String: Any], profile["default"] == nil { report.spacesFromOtherProfiles += 1 }
            let icon: SpaceIcon = {
                let info = space["customInfo"] as? [String: Any]
                let iconType = info?["iconType"] as? [String: Any]
                if let emoji = iconType?["emoji_v2"] as? String, !emoji.isEmpty { return .emoji(emoji) }
                return .symbol("circle.fill")
            }()
            spaces.append(
                Space(
                    id: id(spaceID),
                    title: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Imported Space",
                    icon: icon,
                    profileID: profileID,
                    pinned: pinnedID.map { children(of: $0).compactMap { node($0, pinned: true) } } ?? [],
                    today: unpinnedID.map { children(of: $0).compactMap { node($0, pinned: false) } } ?? []
                ))
        }
        report.spaces = spaces.count

        // Favorites: topAppsContainerIDs = [ {profile}, containerID, … ]; take the default profile's.
        var favorites: [Tab] = []
        let topApps = main["topAppsContainerIDs"] as? [Any] ?? []
        var i = 0
        while i + 1 < topApps.count {
            if let profile = topApps[i] as? [String: Any], profile["default"] != nil, let containerID = topApps[i + 1] as? String {
                favorites = children(of: containerID).compactMap { itemID in
                    guard let item = items[itemID], let data = item["data"] as? [String: Any], let tabData = data["tab"] as? [String: Any]
                    else { return nil }
                    return makeTab(item: item, data: tabData, id: id(itemID), pinned: true)
                }
                break
            }
            i += 2
        }
        report.favorites = favorites.count

        return Result(spaces: spaces, favorites: favorites, report: report)
    }

    #if os(macOS)
        /// Where Arc keeps archived tabs on macOS.
        public static var defaultArchiveURL: URL {
            defaultSidebarURL.deletingLastPathComponent().appending(path: "StorableArchiveItems.json")
        }
    #endif

    #if os(macOS)
        /// Where Arc caches the icons of sidebar items (Favorites, pinned and Today tabs).
        public static var defaultIconCacheURL: URL {
            defaultSidebarURL.deletingLastPathComponent().appending(path: "SidebarItemsFaviconCache")
        }
    #endif

    /// Icons for imported tabs from Arc's sidebar icon cache, one PNG per host. Arc names each file after the
    /// MD5 of the item's ID, which Nera keeps as the tab's ID.
    public static func sidebarIcons(for tabs: [Tab], cache: URL) -> [String: Data] {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var icons: [String: Data] = [:]
        for tab in tabs {
            guard let host = tab.url?.host()?.lowercased(), icons[host] == nil else { continue }
            let name = Insecure.MD5.hash(data: Data(tab.id.uuidString.uppercased().utf8)).map { String(format: "%02x", $0) }.joined()
            guard let data = try? Data(contentsOf: cache.appending(path: name)), data.count < 256_000, data.starts(with: png) else {
                continue
            }
            icons[host] = data
        }
        return icons
    }

    /// Parses Arc's `StorableArchiveItems.json` into archived tabs, newest first. Items that weren't archived
    /// from a Space (Little Arc, unknown sources) or have no web address are left out. Untrusted input: never traps.
    public static func parseArchive(data: Data, uuid: () -> UUID = { UUID() }) -> [ArchivedTab] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var tabs: [ArchivedTab] = []
        for (itemID, item) in keyedPairs(root["items"]).prefix(BrowserImport.limit) {
            guard let source = item["source"] as? [String: Any], let space = source["space"] as? [String: Any],
                let rawSpace = space["_0"] as? String, let spaceID = UUID(uuidString: rawSpace),
                let sidebarItem = item["sidebarItem"] as? [String: Any], let data = sidebarItem["data"] as? [String: Any],
                let tabData = data["tab"] as? [String: Any],
                let tab = makeTab(item: sidebarItem, data: tabData, id: UUID(uuidString: itemID) ?? uuid(), pinned: false),
                BrowserImport.webURL(tab.url?.absoluteString) != nil
            else { continue }
            let archivedAt = (item["archivedAt"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) ?? tab.lastActiveAt
            tabs.append(ArchivedTab(tab: tab, spaceID: spaceID, archivedAt: archivedAt))
        }
        return tabs.sorted { $0.archivedAt > $1.archivedAt }
    }

    // MARK: Helpers

    private static func makeTab(item: [String: Any], data: [String: Any], id: UUID, pinned: Bool) -> Tab? {
        guard let raw = data["savedURL"] as? String, let url = URL(string: raw) else { return nil }
        let title = (item["title"] as? String) ?? (data["savedTitle"] as? String) ?? ""
        // Arc encodes dates as seconds since 2001-01-01 (Swift's default Date coding).
        let active = (data["timeLastActiveAt"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date()
        let muted = (data["savedMuteStatus"] as? String) == "muted"
        return Tab(id: id, url: url, title: title, homeURL: pinned ? url : nil, lastActiveAt: active, isMuted: muted)
    }

    /// Arc stores ordered dictionaries as `[key, value, key, value, …]`. Also accepts `[{"id": …}]`.
    static func keyedPairs(_ value: Any?) -> [(String, [String: Any])] {
        guard let array = value as? [Any] else { return [] }
        var result: [(String, [String: Any])] = []
        var i = 0
        while i < array.count {
            if let key = array[i] as? String, i + 1 < array.count, let obj = array[i + 1] as? [String: Any] {
                result.append((key, obj))
                i += 2
            } else if let obj = array[i] as? [String: Any], let key = obj["id"] as? String {
                result.append((key, obj))
                i += 1
            } else {
                i += 1
            }
        }
        return result
    }

    /// `["pinned", id, "unpinned", id]` or `[{"pinned": {}}, id, …]`.
    static func labeledPairs(_ value: Any?) -> [(String, String)] {
        guard let array = value as? [Any] else { return [] }
        var result: [(String, String)] = []
        var i = 0
        while i + 1 < array.count {
            let label = (array[i] as? String) ?? (array[i] as? [String: Any])?.keys.first
            if let label, let id = array[i + 1] as? String { result.append((label, id)) }
            i += 2
        }
        return result
    }
}
