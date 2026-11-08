// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SQLite3
import Testing

@testable import BrowserData

/// Sign-ins imported before an extension was installed must survive Chromium switching to its startup folder.
@Suite("Chromium profile repair")
struct ChromiumProfileRepairTests {
    let profile = UUID()

    struct Row {
        let host, name, value: String
        init(_ host: String, _ name: String, _ value: String) {
            self.host = host
            self.name = name
            self.value = value
        }
    }

    func makeCookies(_ url: URL, version: String = "24", rows: [Row]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES('version','\(version)');", nil, nil, nil)
        sqlite3_exec(
            db, "CREATE TABLE cookies(host_key TEXT, name TEXT, path TEXT, value TEXT, encrypted_value BLOB, creation_utc INTEGER)", nil,
            nil, nil)
        sqlite3_exec(db, "CREATE UNIQUE INDEX cookies_unique_index ON cookies(host_key, name, path)", nil, nil, nil)
        for row in rows {
            sqlite3_exec(db, "INSERT INTO cookies VALUES('\(row.host)', '\(row.name)', '/', '\(row.value)', x'00', 1)", nil, nil, nil)
        }
    }

    func values(_ url: URL) -> [String: String] {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT host_key || '/' || name, value FROM cookies", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        var out: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            out[String(cString: sqlite3_column_text(statement, 0))] = String(cString: sqlite3_column_text(statement, 1))
        }
        return out
    }

    func root() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "chromium-repair-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func importedSignInsAreMergedIntoTheStartupFolderOnce() throws {
        let r = root()
        let old = r.appending(path: "Profile-\(profile.uuidString)/Cookies")
        let main = r.appending(path: "Default/Cookies")
        try makeCookies(old, rows: [Row(".github.com", "user_session", "imported"), Row(".google.com", "SID", "imported")])
        try makeCookies(main, rows: [Row(".github.com", "user_session", "newer"), Row(".x.com", "auth", "browsed")])
        #expect(ChromiumProfileRepair.repair(root: r, profileID: profile) == .merged(added: 1))
        #expect(values(main) == [".github.com/user_session": "newer", ".google.com/SID": "imported", ".x.com/auth": "browsed"])
        let left = try FileManager.default.contentsOfDirectory(atPath: r.path)
        #expect(!left.contains("Profile-\(profile.uuidString)") && left.contains { $0.hasPrefix("Profile-\(profile.uuidString).moved-") })
        #expect(ChromiumProfileRepair.repair(root: r, profileID: profile) == .nothingToDo, "only once")
    }

    @Test func aFreshStartupFolderGetsTheCookiesAsTheyAre() throws {
        let r = root()
        try makeCookies(r.appending(path: "Profile-\(profile.uuidString)/Cookies"), rows: [Row(".github.com", "user_session", "imported")])
        #expect(ChromiumProfileRepair.repair(root: r, profileID: profile) == .copied)
        #expect(values(r.appending(path: "Default/Cookies")) == [".github.com/user_session": "imported"])
    }

    @Test func differentFormatsAreLeftAlone() throws {
        let r = root()
        try makeCookies(r.appending(path: "Profile-\(profile.uuidString)/Cookies"), version: "23", rows: [Row(".a.example", "n", "v")])
        try makeCookies(r.appending(path: "Default/Cookies"), version: "24", rows: [])
        #expect(ChromiumProfileRepair.repair(root: r, profileID: profile) == .incompatible)
        #expect(FileManager.default.fileExists(atPath: r.appending(path: "Profile-\(profile.uuidString)").path), "kept for a later fix")
        #expect(ChromiumProfileRepair.repair(root: root(), profileID: profile) == .nothingToDo)
    }
}
