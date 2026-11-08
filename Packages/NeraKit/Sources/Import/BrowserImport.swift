// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import BrowserData
public import Foundation
import SQLite3

/// A page from another browser's history.
public struct ImportedVisit: Equatable, Sendable {
    /// The page.
    public var url: URL
    /// Its title.
    public var title: String
    /// Most recent visit.
    public var lastVisit: Date
    /// Number of visits.
    public var visitCount: Int

    /// Creates a visit.
    public init(url: URL, title: String, lastVisit: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
}

/// Parses other browsers' bookmark and history files. All input is untrusted: parsers never trap, only
/// `http`/`https` links are kept (no `javascript:` bookmarklets), and sizes are capped.
public enum BrowserImport {
    /// Most bookmarks or history entries read from one file.
    public static let limit = 100_000

    static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    // MARK: Chromium (Chrome, Arc, Brave, Edge)

    /// Chromium's `Bookmarks` JSON: the bar, "Other" and mobile roots become folders.
    public static func chromiumBookmarks(_ data: Data, uuid: () -> UUID = { UUID() }) throws -> [Bookmark] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = root["roots"] as? [String: Any]
        else { throw BrowserImportError.unrecognizedFile }
        var budget = limit
        func node(_ any: Any?, depth: Int) -> Bookmark? {
            guard budget > 0, depth < 64, let dict = any as? [String: Any] else { return nil }
            budget -= 1
            let title = dict["name"] as? String ?? ""
            if dict["type"] as? String == "folder" {
                let children = (dict["children"] as? [Any] ?? []).compactMap { node($0, depth: depth + 1) }
                return .folder(id: uuid(), title: title, children: children)
            }
            guard let url = webURL(dict["url"] as? String) else { return nil }
            return .link(id: uuid(), title: title, url: url)
        }
        let names = [("bookmark_bar", "Bookmarks Bar"), ("other", "Other Bookmarks"), ("synced", "Mobile Bookmarks")]
        return names.compactMap { key, title in
            guard var folder = node(roots[key], depth: 0), !(folder.children ?? []).isEmpty else { return nil }
            folder.title = title
            return folder
        }
    }

    /// Chromium's `History` SQLite database (times are microseconds since 1601).
    public static func chromiumHistory(at file: URL) throws -> [ImportedVisit] {
        try SQLiteSnapshot(of: file).rows(
            "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT \(limit)"
        ) { row in
            guard let url = webURL(row.text(0)) else { return nil }
            let seconds = Double(row.int(3)) / 1_000_000 - 11_644_473_600
            return ImportedVisit(
                url: url, title: row.text(1) ?? "", lastVisit: Date(timeIntervalSince1970: seconds), visitCount: max(1, row.int(2)))
        }
    }

    // MARK: Safari

    /// Chromium's `Favicons` database: one icon per host (the 32-pixel one when there is one), PNG only.
    public static func chromiumFavicons(at file: URL, limit: Int = 5_000) throws -> [String: Data] {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var icons: [String: Data] = [:]
        let sql = """
            SELECT m.page_url, b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
            WHERE b.width <= 64 ORDER BY b.width DESC LIMIT \(limit * 4)
            """
        _ = try SQLiteSnapshot(of: file).rows(sql) { row -> Int? in
            guard icons.count < limit, let host = webURL(row.text(0))?.host()?.lowercased(), icons[host] == nil,
                let data = row.blob(1), data.count < 64_000, data.starts(with: png)
            else { return nil }
            icons[host] = data
            return 1
        }
        return icons
    }

    /// Safari's `Bookmarks.plist`. Favorites and the Bookmarks Menu keep their names; Reading List is included.
    public static func safariBookmarks(_ data: Data, uuid: () -> UUID = { UUID() }) throws -> [Bookmark] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            root["WebBookmarkType"] as? String == "WebBookmarkTypeList"
        else { throw BrowserImportError.unrecognizedFile }
        var budget = limit
        func node(_ any: Any, depth: Int) -> Bookmark? {
            guard budget > 0, depth < 64, let dict = any as? [String: Any] else { return nil }
            budget -= 1
            switch dict["WebBookmarkType"] as? String {
            case "WebBookmarkTypeList":
                let raw = dict["Title"] as? String ?? ""
                let title =
                    switch raw {
                    case "BookmarksBar": "Favorites"
                    case "BookmarksMenu": "Bookmarks Menu"
                    case "com.apple.ReadingList": "Reading List"
                    default: raw
                    }
                let children = (dict["Children"] as? [Any] ?? []).compactMap { node($0, depth: depth + 1) }
                return children.isEmpty && depth > 0 && raw.isEmpty ? nil : .folder(id: uuid(), title: title, children: children)
            case "WebBookmarkTypeLeaf":
                guard let url = webURL(dict["URLString"] as? String) else { return nil }
                let title = (dict["URIDictionary"] as? [String: Any])?["title"] as? String ?? url.host() ?? ""
                return .link(id: uuid(), title: title, url: url)
            default:
                return nil  // proxies such as History
            }
        }
        return (root["Children"] as? [Any] ?? []).compactMap { node($0, depth: 1) }.filter { !$0.isFolder || !($0.children ?? []).isEmpty }
    }

    /// Safari's `History.db` (times are seconds since 2001).
    public static func safariHistory(at file: URL) throws -> [ImportedVisit] {
        try SQLiteSnapshot(of: file).rows(
            """
            SELECT i.url, (SELECT v.title FROM history_visits v WHERE v.history_item = i.id ORDER BY v.visit_time DESC LIMIT 1),
              i.visit_count, (SELECT max(v.visit_time) FROM history_visits v WHERE v.history_item = i.id) AS last
            FROM history_items i ORDER BY last DESC LIMIT \(limit)
            """
        ) { row in
            guard let url = webURL(row.text(0)) else { return nil }
            return ImportedVisit(
                url: url, title: row.text(1) ?? "", lastVisit: Date(timeIntervalSinceReferenceDate: row.double(3)),
                visitCount: max(1, row.int(2)))
        }
    }

    // MARK: Firefox

    /// Firefox's `places.sqlite` bookmarks: the toolbar, menu, "Other" and mobile roots become folders.
    public static func firefoxBookmarks(at file: URL, uuid: () -> UUID = { UUID() }) throws -> [Bookmark] {
        struct Row {
            let id: Int
            let parent: Int
            let type: Int
            let title: String
            let url: String?
        }
        let rows = try SQLiteSnapshot(of: file).rows(
            """
            SELECT b.id, b.parent, b.type, b.title, p.url FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk
            ORDER BY b.parent, b.position LIMIT \(limit)
            """
        ) { Row(id: $0.int(0), parent: $0.int(1), type: $0.int(2), title: $0.text(3) ?? "", url: $0.text(4)) }
        let byParent = Dictionary(grouping: rows, by: \.parent)
        let guids = try SQLiteSnapshot(of: file).rows("SELECT id, guid FROM moz_bookmarks WHERE parent = 1 OR id = 1") {
            ($0.int(0), $0.text(1) ?? "")
        }
        func children(of id: Int, depth: Int) -> [Bookmark] {
            guard depth < 64 else { return [] }
            return (byParent[id] ?? []).compactMap { row in
                switch row.type {
                case 2: return .folder(id: uuid(), title: row.title, children: children(of: row.id, depth: depth + 1))
                case 1: return webURL(row.url).map { .link(id: uuid(), title: row.title.isEmpty ? ($0.host() ?? "") : row.title, url: $0) }
                default: return nil
                }
            }
        }
        let names = [
            "toolbar_____": "Bookmarks Toolbar", "menu________": "Bookmarks Menu", "unfiled_____": "Other Bookmarks",
            "mobile______": "Mobile Bookmarks",
        ]
        return ["toolbar_____", "menu________", "unfiled_____", "mobile______"].compactMap { guid in
            guard let id = guids.first(where: { $0.1 == guid })?.0 else { return nil }
            let kids = children(of: id, depth: 1)
            return kids.isEmpty ? nil : .folder(id: uuid(), title: names[guid] ?? guid, children: kids)
        }
    }

    /// Firefox's `places.sqlite` history (times are microseconds since 1970).
    public static func firefoxHistory(at file: URL) throws -> [ImportedVisit] {
        try SQLiteSnapshot(of: file).rows(
            "SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 ORDER BY last_visit_date DESC LIMIT \(limit)"
        ) { row in
            guard let url = webURL(row.text(0)) else { return nil }
            return ImportedVisit(
                url: url, title: row.text(1) ?? "", lastVisit: Date(timeIntervalSince1970: Double(row.int(3)) / 1_000_000),
                visitCount: max(1, row.int(2)))
        }
    }
}
