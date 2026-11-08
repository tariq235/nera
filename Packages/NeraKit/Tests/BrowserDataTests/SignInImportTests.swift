// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CommonCrypto
import Foundation
import SQLite3
import Testing

@testable import BrowserData

/// Sign-in import: Chromium's encrypted cookies are decrypted in memory, expired ones are dropped.
@Suite("Sign-in import")
struct SignInImportTests {
    let key = ChromiumCookies.derivedKey(password: Data("peanuts".utf8))

    /// Encrypts like Chromium on macOS ("v10", AES-128-CBC, IV of spaces, optional domain hash first).
    func encrypt(_ value: String, host: String, withHash: Bool) -> Data {
        var plain = Data()
        if withHash { plain.append(Data(repeating: 0xAB, count: 32)) }
        plain.append(Data(value.utf8))
        var out = Data(count: plain.count + kCCBlockSizeAES128)
        var length = 0
        let capacity = out.count
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        _ = out.withUnsafeMutableBytes { o in
            plain.withUnsafeBytes { p in
                key.withUnsafeBytes { k in
                    CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, key.count,
                        iv, p.baseAddress, plain.count, o.baseAddress, capacity, &length)
                }
            }
        }
        return Data("v10".utf8) + out.prefix(length)
    }

    /// Microseconds since 1601, as Chromium stores times.
    func chromiumTime(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) }

    func makeDatabase(version: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cookies-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES('version','\(version)');", nil, nil, nil)
        sqlite3_exec(
            db,
            """
            CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER,
            is_secure INTEGER, is_httponly INTEGER, samesite INTEGER, has_expires INTEGER)
            """, nil, nil, nil)
        struct Row {
            let host, name, value: String
            let expires: Date
            let sameSite: Int
        }
        let rows = [
            Row(host: ".github.com", name: "user_session", value: "s3cret", expires: Date().addingTimeInterval(86400), sameSite: 1),
            Row(host: "mail.google.com", name: "SID", value: "abc", expires: Date().addingTimeInterval(86400), sameSite: 2),
            Row(host: ".old.example", name: "gone", value: "x", expires: Date().addingTimeInterval(-60), sameSite: 1),  // expired
        ]
        for row in rows {
            let (host, name, value, expires, sameSite) = (row.host, row.name, row.value, row.expires, row.sameSite)
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO cookies VALUES(?, ?, '', ?, '/', ?, 1, 1, ?, 1)", -1, &statement, nil)
            let blob = encrypt(value, host: host, withHash: version >= 24)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, host, -1, transient)
            sqlite3_bind_text(statement, 2, name, -1, transient)
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(blob.count), transient) }
            sqlite3_bind_int64(statement, 4, chromiumTime(expires))
            sqlite3_bind_int(statement, 5, Int32(sameSite))
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        return url
    }

    @Test(arguments: [23, 24]) func decryptsUnexpiredCookies(version: Int) throws {
        let db = try makeDatabase(version: version)
        defer { try? FileManager.default.removeItem(at: db) }
        let cookies = try ChromiumCookies.read(database: db, key: key).sorted { $0.name > $1.name }
        #expect(cookies.map(\.name) == ["user_session", "SID"], "the expired cookie is dropped")
        #expect(cookies.map(\.value) == ["s3cret", "abc"])
        #expect(cookies[0].domain == ".github.com" && cookies[0].host == "github.com")
        #expect(cookies[0].isSecure && cookies[0].isHTTPOnly && cookies[0].sameSite == "Lax" && cookies[1].sameSite == "Strict")
        #expect(abs((cookies[0].expires?.timeIntervalSinceNow ?? 0) - 86400) < 5)
    }

    @Test func wrongKeyReadsNothing() throws {
        let db = try makeDatabase(version: 24)
        defer { try? FileManager.default.removeItem(at: db) }
        let other = ChromiumCookies.derivedKey(password: Data("not-it".utf8))
        #expect(try !ChromiumCookies.read(database: db, key: other).contains { $0.value == "s3cret" || $0.value == "abc" })
    }

    @Test func onlyChromiumBrowsersHaveKeychainItems() {
        #expect(ChromiumCookies.keychainItem(for: .arc)?.service == "Arc Safe Storage")  // naming: import-reference
        #expect(ChromiumCookies.keychainItem(for: .chrome)?.account == "Chrome")
        #expect(ChromiumCookies.keychainItem(for: .safari) == nil && ChromiumCookies.keychainItem(for: .firefox) == nil)
    }

    @Test func savedPasswordsBecomeAnApplePasswordsCSV() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "logins-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        let schema = "CREATE TABLE logins(origin_url TEXT, username_value TEXT, password_value BLOB, blacklisted_by_user INTEGER)"
        sqlite3_exec(db, schema, nil, nil, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (site, user, password, never) in [
            ("https://github.com/login", "me@example.com", "p,a\"ss", 0), ("https://bank.example/", "", "x", 1),
            ("https://github.com/login", "me@example.com", "p,a\"ss", 0),
        ] {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO logins VALUES(?, ?, ?, ?)", -1, &statement, nil)
            let blob = encrypt(password, host: "", withHash: false)
            sqlite3_bind_text(statement, 1, site, -1, transient)
            sqlite3_bind_text(statement, 2, user, -1, transient)
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(blob.count), transient) }
            sqlite3_bind_int(statement, 4, Int32(never))
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        sqlite3_close(db)
        let logins = try ChromiumPasswords.read(database: url, key: key)
        #expect(logins.count == 1, "never-save entries and duplicates are skipped")
        #expect(logins.first?.password == "p,a\"ss")
        let csv = ChromiumPasswords.csv(logins)
        #expect(csv == "name,url,username,password,note\ngithub.com,https://github.com/login,me@example.com,\"p,a\"\"ss\",\n")
    }
}
