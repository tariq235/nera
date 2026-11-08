// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
import SQLite3

/// Keeps a profile's Chromium data in the folder Chromium actually reads.
///
/// Nera's main profile is Chromium's startup profile (where extensions load, ADR-0012), and Chromium keeps its
/// startup profile in `Default` inside its data folder. Builds up to 8 used `Profile-<id>` for that profile until an
/// extension was installed, then `Default` after the restart, which left the sign-ins imported in the welcome
/// behind. This moves them over once: cookies in `Profile-<id>` are merged into `Default` (a cookie both have keeps
/// `Default`'s, the newer), and the old folder is kept, renamed, as a backup. Runs before Chromium starts.
public enum ChromiumProfileRepair {
    /// What the repair did.
    public enum Outcome: Equatable, Sendable {
        /// Nothing to repair.
        case nothingToDo
        /// The old folder's cookies were merged (how many were added).
        case merged(added: Int)
        /// `Default` had no cookie database yet: the old one was copied over.
        case copied
        /// The two databases have different formats: left alone (Chromium would reject a mixed file).
        case incompatible
    }

    /// Repairs `profileID`'s data inside Chromium's data folder `root`.
    @discardableResult
    public static func repair(root: URL, profileID: UUID) -> Outcome {
        let fm = FileManager.default
        let old = root.appending(path: "Profile-\(profileID.uuidString)")
        let oldCookies = old.appending(path: "Cookies")
        guard fm.fileExists(atPath: oldCookies.path) else { return .nothingToDo }
        let main = root.appending(path: "Default")
        let mainCookies = main.appending(path: "Cookies")
        let outcome: Outcome
        if fm.fileExists(atPath: mainCookies.path) {
            guard let added = merge(from: oldCookies, into: mainCookies) else { return .incompatible }
            outcome = .merged(added: added)
        } else {
            try? fm.createDirectory(at: main, withIntermediateDirectories: true)
            for suffix in ["", "-journal", "-wal"] where fm.fileExists(atPath: oldCookies.path + suffix) {
                try? fm.copyItem(atPath: oldCookies.path + suffix, toPath: mainCookies.path + suffix)
            }
            outcome = .copied
        }
        // Keep the old folder as a backup, out of Chromium's way, so this runs only once.
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? fm.moveItem(at: old, to: root.appending(path: "Profile-\(profileID.uuidString).moved-\(stamp)"))
        return outcome
    }

    /// Adds `source`'s cookies that `destination` doesn't have. Returns how many, or nil if the formats differ.
    static func merge(from source: URL, into destination: URL) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        func scalar(_ sql: String) -> String? {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
                let text = sqlite3_column_text(statement, 0)
            else { return nil }
            return String(cString: text)
        }
        let quoted = source.path.replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(db, "ATTACH DATABASE '\(quoted)' AS old", nil, nil, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_exec(db, "DETACH DATABASE old", nil, nil, nil) }
        let mine = scalar("SELECT value FROM main.meta WHERE key = 'version'")
        let theirs = scalar("SELECT value FROM old.meta WHERE key = 'version'")
        let columns = scalar("SELECT group_concat(name) FROM pragma_table_info('cookies')")
        let oldColumns = scalar("SELECT group_concat(name) FROM old.pragma_table_info('cookies')")
        guard let mine, mine == theirs, let columns, columns == oldColumns else { return nil }
        let before = Int(scalar("SELECT count(*) FROM main.cookies") ?? "0") ?? 0
        guard sqlite3_exec(db, "INSERT OR IGNORE INTO main.cookies SELECT * FROM old.cookies", nil, nil, nil) == SQLITE_OK else {
            return nil
        }
        let after = Int(scalar("SELECT count(*) FROM main.cookies") ?? "0") ?? 0
        return after - before
    }
}
