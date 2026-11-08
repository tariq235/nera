// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import CryptoKit
import Foundation
import SQLite3
import Testing

@testable import Import

/// The welcome screen's extra imports: Arc's archive, another browser's extensions and site icons.
@Suite("Welcome imports")
struct OnboardingImportTests {
    func temporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nera-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func arcArchiveKeepsSpaceTabsWithWebAddressesNewestFirst() {
        let space = "AAAAAAAA-0000-0000-0000-000000000001"
        func item(_ id: String, url: String, at: Double, source: String) -> String {
            """
            "\(id)", {"source": \(source), "reason": "manual", "archivedAt": \(at),
              "sidebarItem": {"id": "\(id)", "title": null, "childrenIds": [],
                "data": {"tab": {"savedURL": "\(url)", "savedTitle": "T \(id)", "savedMuteStatus": "allowMedia"}}}}
            """
        }
        let json = """
            {"version": 1, "items": [
              \(item("BBBBBBBB-0000-0000-0000-000000000001", url: "https://old.example", at: 100, source: #"{"space": {"_0": "\#(space)"}}"#)),
              \(item("BBBBBBBB-0000-0000-0000-000000000002", url: "https://new.example", at: 200, source: #"{"space": {"_0": "\#(space)"}}"#)),
              \(item("BBBBBBBB-0000-0000-0000-000000000003", url: "javascript:alert(1)", at: 300, source: #"{"space": {"_0": "\#(space)"}}"#)),
              \(item("BBBBBBBB-0000-0000-0000-000000000004", url: "https://little.example", at: 400, source: #"{"littleArc": {}}"#)),
              "broken", 42
            ]}
            """
        let tabs = ArcImporter.parseArchive(data: Data(json.utf8))
        #expect(tabs.map { $0.tab.url?.host() } == ["new.example", "old.example"])
        #expect(tabs.allSatisfy { $0.spaceID == UUID(uuidString: space) })
        #expect(
            tabs[0].archivedAt == Date(timeIntervalSinceReferenceDate: 200) && tabs[0].tab.title == "T BBBBBBBB-0000-0000-0000-000000000002"
        )
        #expect(ArcImporter.parseArchive(data: Data("nope".utf8)).isEmpty)
    }

    @Test func listsOnlyWebStoreExtensionsWithStateAndLocalizedNames() throws {
        let profile = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: profile) }
        func add(_ id: String, manifest: String, files: [String: Data] = [:]) throws {
            let dir = profile.appending(path: "Extensions/\(id)/1.0_0")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: dir.appending(path: "manifest.json"))
            for (path, data) in files {
                try FileManager.default.createDirectory(
                    at: dir.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: dir.appending(path: path))
            }
        }
        let store = #""update_url": "https://clients2.google.com/service/update2/crx""#
        let a = String(repeating: "a", count: 32)
        let b = String(repeating: "b", count: 32)
        let c = String(repeating: "c", count: 32)
        try add(
            a,
            manifest:
                #"{"name": "__MSG_appName__", "default_locale": "en", "manifest_version": 3, "icons": {"16": "i16.png", "128": "i128.png"}, \#(store)}"#,
            files: ["_locales/en/messages.json": Data(#"{"appName": {"message": "Password Keeper"}}"#.utf8), "i128.png": Data([1, 2, 3])])
        try add(b, manifest: #"{"name": "Old Blocker", "manifest_version": 2, \#(store)}"#)
        try add(c, manifest: #"{"name": "Built In", "manifest_version": 3}"#)  // not from the Web Store
        let prefs = #"{"extensions": {"settings": {"\#(a)": {"disable_reasons": []}, "\#(b)": {"disable_reasons": [2]}}}}"#
        try Data(prefs.utf8).write(to: profile.appending(path: "Secure Preferences"))

        let found = BrowserExtensions.list(inProfile: profile)
        #expect(found.map(\.name) == ["Password Keeper", "Old Blocker"])
        #expect(found[0].wasEnabled && found[0].isSupported && found[0].icon == Data([1, 2, 3]))
        #expect(!found[1].wasEnabled && !found[1].isSupported)
        #expect(BrowserExtensions.list(inProfile: profile.appending(path: "missing")).isEmpty)
    }

    @Test func readsOnePNGIconPerHostFromChromiumFavicons() throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Favicons")
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        let png32 = Data([0x89, 0x50, 0x4E, 0x47, 32])
        let png16 = Data([0x89, 0x50, 0x4E, 0x47, 16])
        let schema = """
            CREATE TABLE icon_mapping(id INTEGER PRIMARY KEY, page_url TEXT, icon_id INTEGER);
            CREATE TABLE favicon_bitmaps(id INTEGER PRIMARY KEY, icon_id INTEGER, image_data BLOB, width INTEGER);
            INSERT INTO icon_mapping VALUES (1, 'https://www.example.com/a', 1), (2, 'https://www.example.com/b', 1),
              (3, 'https://other.example/', 2), (4, 'javascript:x', 1);
            INSERT INTO favicon_bitmaps VALUES (1, 1, X'\(png16.hex)', 16), (2, 1, X'\(png32.hex)', 32), (3, 2, X'00010203', 32);
            """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let icons = try BrowserImport.chromiumFavicons(at: file)
        #expect(icons == ["www.example.com": png32], "the largest PNG per host; non-PNG data is dropped")
    }
}

extension OnboardingImportTests {
    @Test func findsArcSidebarIconsByTheMD5OfTheItemID() throws {
        let cache = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: cache) }
        let id = try #require(UUID(uuidString: "00A7A5AB-C52B-4E28-9BDD-D20FC20CA9AF"))
        let name = Insecure.MD5.hash(data: Data(id.uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1])
        try png.write(to: cache.appending(path: name))
        let tab = Tab(id: id, url: URL(string: "https://Claude.ai/new"), title: "", lastActiveAt: Date())
        let other = Tab(id: UUID(), url: URL(string: "https://none.example"), title: "", lastActiveAt: Date())
        #expect(ArcImporter.sidebarIcons(for: [tab, other], cache: cache) == ["claude.ai": png])
    }
}

extension Data {
    fileprivate var hex: String { map { String(format: "%02x", $0) }.joined() }
}
