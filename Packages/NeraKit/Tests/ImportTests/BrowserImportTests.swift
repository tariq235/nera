// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import BrowserData
import EngineTestSupport
import Foundation
import TestSupport
import Testing

@testable import Import

/// bookmarks and history from other browsers.
@Suite("Browser import")
struct BrowserImportTests {
    func database(_ sql: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "nera-fixture-\(UUID().uuidString).sqlite")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [file.path, sql]
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return file
    }

    @Test func chromiumBookmarksKeepFoldersAndDropBookmarklets() throws {
        let json = #"""
            {"roots": {
              "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
                {"type": "url", "name": "Swift", "url": "https://swift.org/"},
                {"type": "url", "name": "Bookmarklet", "url": "javascript:alert(1)"},
                {"type": "folder", "name": "Work", "children": [{"type": "url", "name": "Docs", "url": "https://docs.example/"}]}
              ]},
              "other": {"type": "folder", "name": "Other", "children": []},
              "synced": {"type": "folder", "name": "Mobile", "children": [{"type": "url", "name": "M", "url": "http://m.example/"}]}
            }}
            """#
        let tree = try BrowserImport.chromiumBookmarks(Data(json.utf8))
        #expect(tree.map(\.title) == ["Bookmarks Bar", "Mobile Bookmarks"], "empty roots are skipped")
        #expect(tree[0].children?.map(\.title) == ["Swift", "Work"], "javascript: bookmarklets are dropped")
        #expect(tree.allLinks.map(\.url?.host) == ["swift.org", "docs.example", "m.example"])
        #expect(throws: BrowserImportError.unrecognizedFile) { try BrowserImport.chromiumBookmarks(Data("[]".utf8)) }
    }

    @Test func chromiumHistoryConvertsWebKitTimes() throws {
        // 13_380_000_000_000_000 µs since 1601 = 2025-01-01T… (just a fixed point to check the epoch shift)
        let db = try database(
            """
            CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER, hidden INTEGER DEFAULT 0);
            INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES ('https://a.example/', 'A', 7, 13380000000000000);
            INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES ('chrome://settings', 'Settings', 1, 13380000000000001);
            INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('https://hidden.example/', 'H', 1, 1, 1);
            """)
        let visits = try BrowserImport.chromiumHistory(at: db)
        #expect(visits.map(\.title) == ["A"], "internal pages and hidden rows are skipped")
        #expect(visits[0].visitCount == 7)
        #expect(abs(visits[0].lastVisit.timeIntervalSince1970 - (13_380_000_000 - 11_644_473_600)) < 1)
    }

    @Test func safariBookmarksMapSpecialFolders() throws {
        let plist: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
                [
                    "WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar",
                    "Children": [
                        ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com/", "URIDictionary": ["title": "Apple"]]
                    ],
                ],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksMenu", "Children": []],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let tree = try BrowserImport.safariBookmarks(data)
        #expect(tree.map(\.title) == ["Favorites"], "proxies and empty folders are skipped")
        #expect(tree[0].children?.first?.title == "Apple")
    }

    @Test func firefoxBookmarksAndHistoryFromPlaces() throws {
        let db = try database(
            """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_date INTEGER, hidden INTEGER DEFAULT 0);
            CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER, title TEXT, guid TEXT);
            INSERT INTO moz_places VALUES (1, 'https://mozilla.org/', 'Mozilla', 3, 1700000000000000, 0);
            INSERT INTO moz_places VALUES (2, 'place:sort=8', 'Recent', 0, NULL, 0);
            INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 'root________');
            INSERT INTO moz_bookmarks VALUES (2, 2, NULL, 1, 0, 'menu', 'menu________');
            INSERT INTO moz_bookmarks VALUES (3, 2, NULL, 1, 1, 'toolbar', 'toolbar_____');
            INSERT INTO moz_bookmarks VALUES (4, 1, 1, 3, 0, 'Mozilla', 'aaaaaaaaaaaa');
            INSERT INTO moz_bookmarks VALUES (5, 1, 2, 3, 1, 'Recent', 'bbbbbbbbbbbb');
            """)
        let tree = try BrowserImport.firefoxBookmarks(at: db)
        #expect(tree.map(\.title) == ["Bookmarks Toolbar"])
        #expect(tree[0].children?.map(\.title) == ["Mozilla"], "place: queries are skipped")
        let history = try BrowserImport.firefoxHistory(at: db)
        #expect(history.map(\.title) == ["Mozilla"] && history[0].lastVisit == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func safariHistory() throws {
        let db = try database(
            """
            CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER);
            CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT);
            INSERT INTO history_items VALUES (1, 'https://webkit.org/', 4);
            INSERT INTO history_visits VALUES (1, 1, 700000000, 'Old title');
            INSERT INTO history_visits VALUES (2, 1, 750000000, 'WebKit');
            """)
        let visits = try BrowserImport.safariHistory(at: db)
        #expect(visits.map(\.title) == ["WebKit"] && visits[0].lastVisit == Date(timeIntervalSinceReferenceDate: 750_000_000))
    }

    @Test func unreadableFilesFailCleanly() {
        #expect(throws: BrowserImportError.unreadable) {
            try BrowserImport.chromiumHistory(at: URL(fileURLWithPath: "/nonexistent/History"))
        }
    }

    @Test func bookmarksHTMLRoundTrips() throws {
        let tree: [Bookmark] = [
            .folder(
                id: UUID(), title: "Dev & <Tools>",
                children: [.link(id: UUID(), title: "Swift \"lang\"", url: URL(string: "https://swift.org/?a=1&b=2")!)]),
            .link(id: UUID(), title: "Top", url: URL(string: "https://top.example/")!),
        ]
        let parsed = try BookmarksHTML.parse(BookmarksHTML.export(tree))
        #expect(parsed.map(\.title) == ["Dev & <Tools>", "Top"])
        #expect(parsed[0].children?.first?.title == "Swift \"lang\"")
        #expect(parsed[0].children?.first?.url?.absoluteString == "https://swift.org/?a=1&b=2")
    }

    @Test func bookmarksHTMLFromOtherBrowsers() throws {
        let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
              <DT><H3 ADD_DATE="1">Toolbar</H3>
              <DL><p>
                <DT><A HREF='https://a.example/' ICON="data:x">A</A>
                <DT><A HREF="javascript:void(0)">JS</A>
              </DL><p>
              <DT><A HREF="https://b.example/">B
            </DL>
            """
        let tree = try BookmarksHTML.parse(html)
        #expect(tree.map(\.title) == ["Toolbar", "B"])
        #expect(tree[0].children?.map(\.title) == ["A"])
        #expect(throws: BrowserImportError.unrecognizedFile) { try BookmarksHTML.parse("<html>nothing</html>") }
    }

    @Test func damagedFilesNeverCrash() throws {
        let html = Data(
            BookmarksHTML.export([
                .folder(id: UUID(), title: "F", children: [.link(id: UUID(), title: "L", url: URL(string: "https://l.example")!)])
            ]).utf8)
        let json = Data(#"{"roots":{"bookmark_bar":{"type":"folder","children":[{"type":"url","url":"https://x.example"}]}}}"#.utf8)
        for seed in UInt64(0)..<1000 * SeededRandom.scale {
            var rng = SeededRandom(seed: seed)
            _ = try? BookmarksHTML.parse(String(decoding: rng.mutate(html), as: UTF8.self))
            _ = try? BrowserImport.chromiumBookmarks(rng.mutate(json))
        }
    }
}

/// Bookmark tree edits (reducer).
@Suite("Bookmarks")
struct BookmarkReducerTests {
    let env = TestEnv()

    @Test func addRenameMoveDeleteAndImport() throws {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let p = s.profiles[0].id
        func run(_ a: BookmarkAction) { _ = Reducer.reduce(&s, .library(.bookmarks(profileID: p, a)), env.reducer) }
        let swift = URL(string: "https://swift.org")!
        run(.add(title: "Swift", url: swift, folderID: nil))
        run(.add(title: "Swift again", url: swift, folderID: nil))
        #expect(s.profiles[0].bookmarkTree.count == 1, "no duplicate in the same folder")
        run(.addFolder(title: "Work", folderID: nil))
        let work = try #require(s.profiles[0].bookmarkTree.last?.id)
        let link = try #require(s.profiles[0].bookmarkTree.first?.id)
        run(.move(link, toFolder: work))
        #expect(s.profiles[0].bookmarkTree.map(\.title) == ["Work"])
        #expect(s.profiles[0].bookmarkTree[0].children?.map(\.title) == ["Swift"])
        run(.move(work, toFolder: work))
        run(.move(work, toFolder: link))
        #expect(s.profiles[0].bookmarkTree.map(\.title) == ["Work"], "no moves into itself or into a link")
        run(.rename(link, title: "Swift.org"))
        #expect(s.profiles[0].bookmarkTree.allLinks.map(\.title) == ["Swift.org"])
        run(
            .importTree([.link(id: UUID(), title: "Imported", url: URL(string: "https://i.example")!)], folderTitle: "Imported from Chrome")
        )
        #expect(s.profiles[0].bookmarkTree.map(\.title) == ["Work", "Imported from Chrome"])
        run(.delete(work))
        #expect(s.profiles[0].bookmarkTree.allLinks.map(\.title) == ["Imported"])
    }

    @Test func librariesWithoutBookmarksStillDecode() throws {
        let json = #"{"id":"6D7B1F2E-6C1B-4E2A-9F0B-1A2B3C4D5E6F","name":"Personal","favorites":[]}"#
        #expect(try JSONDecoder().decode(Profile.self, from: Data(json.utf8)).bookmarkTree.isEmpty)
    }
}
