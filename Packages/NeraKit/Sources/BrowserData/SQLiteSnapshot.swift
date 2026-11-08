// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

package import Foundation
import SQLite3

/// Reads a copy of another app's SQLite database (the original may be open and locked by its browser).
package struct SQLiteSnapshot {
    let copy: URL

    /// Copies `file` (and its write-ahead log) to a private temporary folder.
    package init(of file: URL) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nera-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        copy = dir.appending(path: "db.sqlite")
        do {
            try FileManager.default.copyItem(at: file, to: copy)
        } catch {
            throw BrowserImportError.unreadable
        }
        for suffix in ["-wal", "-shm"] {  // recent changes still in the write-ahead log
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: file.path + suffix), to: URL(fileURLWithPath: copy.path + suffix))
        }
    }

    /// One result row.
    package struct Row {
        let statement: OpaquePointer?
        /// A text column.
        package func text(_ i: Int32) -> String? { sqlite3_column_text(statement, i).map { String(cString: $0) } }
        /// An integer column.
        package func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }
        /// A real column.
        package func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
        /// A blob column.
        package func blob(_ i: Int32) -> Data? {
            let length = Int(sqlite3_column_bytes(statement, i))
            guard length != 0, let bytes = sqlite3_column_blob(statement, i) else { return nil }
            return Data(bytes: bytes, count: length)
        }
    }

    /// Runs a query on the copy (then deletes the copy).
    package func rows<T>(_ sql: String, _ map: (Row) -> T?) throws -> [T] {
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw BrowserImportError.unreadable }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw BrowserImportError.unrecognizedFile }
        var out: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = map(Row(statement: statement)) { out.append(value) }
        }
        return out
    }
}
