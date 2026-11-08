// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
import SQLite3

/// One visited page in a profile's history.
public struct HistoryEntry: Equatable, Hashable, Sendable, Identifiable {
    /// The page.
    public var url: URL
    /// Its last known title (may be empty).
    public var title: String
    /// Most recent visit.
    public var lastVisit: Date
    /// Number of visits.
    public var visitCount: Int

    /// Identity: the URL (one entry per URL and profile).
    public var id: URL { url }

    /// Creates an entry.
    public init(url: URL, title: String, lastVisit: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
}

/// Browsing history, per profile, in a SQLite file next to the library.
///
/// - One row per profile and URL: visits bump the count and the time; title changes update the title.
/// - Only `http`/`https` pages are recorded. Private sessions are never passed in (the shell checks the scope).
/// - Search ranks by frecency: visit count, decayed by days since the last visit.
/// - Thread-safe (one connection behind a lock); calls are short.
public final class HistoryStore: @unchecked Sendable {
    // @unchecked: `db` is only touched while holding `lock`.
    private var db: OpaquePointer?
    private let lock = NSLock()
    /// How long entries are kept.
    public static let retention: TimeInterval = 90 * 86_400

    /// Opens (creating if needed) the history file, or an in-memory store when `fileURL` is nil.
    public init(fileURL: URL?) throws {
        let path = fileURL?.path ?? ":memory:"
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw HistoryError.sqlite(message)
        }
        try exec(
            """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS visits (
              profile TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
              last_visit REAL NOT NULL, visit_count INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (profile, url));
            CREATE INDEX IF NOT EXISTS visits_recent ON visits(profile, last_visit DESC);
            """)
        #if os(iOS)
            if let fileURL {
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
            }
        #endif
    }

    /// `Application Support/<bundle id>/history.sqlite`.
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.nera.browser") throws -> HistoryStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appending(path: bundleID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try HistoryStore(fileURL: dir.appending(path: "history.sqlite"))
    }

    deinit { sqlite3_close(db) }

    /// Whether a URL belongs in history.
    public static func isRecordable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// Records a visit (new row, or count + 1 and a new time). A non-empty title replaces the stored one.
    public func recordVisit(_ url: URL, title: String?, profileID: UUID, at date: Date = Date()) {
        guard Self.isRecordable(url) else { return }
        run(
            """
            INSERT INTO visits(profile, url, title, last_visit, visit_count) VALUES (?1, ?2, COALESCE(?3, ''), ?4, 1)
            ON CONFLICT(profile, url) DO UPDATE SET visit_count = visit_count + 1, last_visit = excluded.last_visit,
              title = CASE WHEN ?3 IS NULL OR ?3 = '' THEN title ELSE ?3 END
            """,
            [.text(profileID.uuidString), .text(url.absoluteString), title.map { .text($0) } ?? .null, .real(date.timeIntervalSince1970)])
    }

    /// Adds history imported from another browser in one transaction. Existing entries keep the larger visit
    /// count and the later visit time. Returns how many pages were added or updated.
    @discardableResult
    public func importVisits(_ visits: [HistoryEntry], profileID: UUID) -> Int {
        var count = 0
        lock.withLock {
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            var statement: OpaquePointer?
            defer {
                sqlite3_finalize(statement)
                sqlite3_exec(db, "COMMIT", nil, nil, nil)
            }
            let sql = """
                INSERT INTO visits(profile, url, title, last_visit, visit_count) VALUES (?1, ?2, ?3, ?4, ?5)
                ON CONFLICT(profile, url) DO UPDATE SET visit_count = max(visit_count, excluded.visit_count),
                  last_visit = max(last_visit, excluded.last_visit), title = CASE WHEN title = '' THEN excluded.title ELSE title END
                """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            for visit in visits where Self.isRecordable(visit.url) {
                sqlite3_reset(statement)
                Value.text(profileID.uuidString).bind(statement, 1)
                Value.text(visit.url.absoluteString).bind(statement, 2)
                Value.text(visit.title).bind(statement, 3)
                Value.real(visit.lastVisit.timeIntervalSince1970).bind(statement, 4)
                Value.int(max(1, visit.visitCount)).bind(statement, 5)
                if sqlite3_step(statement) == SQLITE_DONE { count += 1 }
            }
        }
        return count
    }

    /// Updates the title of an existing entry (pages often set their title after the visit is recorded).
    public func updateTitle(_ url: URL, title: String, profileID: UUID) {
        guard !title.isEmpty else { return }
        run(
            "UPDATE visits SET title = ?3 WHERE profile = ?1 AND url = ?2",
            [.text(profileID.uuidString), .text(url.absoluteString), .text(title)])
    }

    /// Most recent first, optionally only visits before `before` (paging).
    public func recent(profileID: UUID, limit: Int = 200, before: Date? = nil) -> [HistoryEntry] {
        query(
            "SELECT url, title, last_visit, visit_count FROM visits WHERE profile = ?1 AND last_visit < ?2 ORDER BY last_visit DESC LIMIT ?3",
            [.text(profileID.uuidString), .real((before ?? .distantFuture).timeIntervalSince1970), .int(limit)])
    }

    /// Entries whose URL or title contains every word of `text`, best match first (frecency).
    public func search(_ text: String, profileID: UUID, limit: Int = 50, now: Date = Date()) -> [HistoryEntry] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).prefix(6).map(String.init)
        guard !words.isEmpty else { return recent(profileID: profileID, limit: limit) }
        var sql = "SELECT url, title, last_visit, visit_count FROM visits WHERE profile = ?1"
        var args: [Value] = [.text(profileID.uuidString), .real(now.timeIntervalSince1970), .int(limit)]
        for word in words {
            let n = args.count + 1
            sql += " AND (lower(url) LIKE ?\(n) ESCAPE '\\' OR lower(title) LIKE ?\(n) ESCAPE '\\')"
            args.append(.text("%" + Self.escapeLike(word) + "%"))
        }
        sql += " ORDER BY visit_count / (1.0 + max(0, ?2 - last_visit) / 86400.0) DESC, last_visit DESC LIMIT ?3"
        return query(sql, args)
    }

    /// The most-used sites (one entry per host, best first by frecency), for the start page.
    public func topSites(profileID: UUID, limit: Int = 8, now: Date = Date()) -> [HistoryEntry] {
        let candidates = query(
            "SELECT url, title, last_visit, visit_count FROM visits WHERE profile = ?1"
                + " ORDER BY visit_count / (1.0 + max(0, ?2 - last_visit) / 86400.0) DESC LIMIT ?3",
            [.text(profileID.uuidString), .real(now.timeIntervalSince1970), .int(limit * 20)])
        var hosts = Set<String>()
        return Array(candidates.filter { hosts.insert($0.url.host()?.lowercased() ?? "").inserted }.prefix(limit))
    }

    /// Removes one URL from a profile's history.
    public func delete(_ url: URL, profileID: UUID) {
        run("DELETE FROM visits WHERE profile = ?1 AND url = ?2", [.text(profileID.uuidString), .text(url.absoluteString)])
    }

    /// "Clear browsing history": everything visited since `since` (all time when nil) in a profile.
    public func clear(profileID: UUID, since: Date? = nil) {
        run(
            "DELETE FROM visits WHERE profile = ?1 AND last_visit >= ?2",
            [.text(profileID.uuidString), .real((since ?? .distantPast).timeIntervalSince1970)])
    }

    /// Drops entries older than ``retention``, in every profile.
    public func prune(now: Date = Date()) {
        run("DELETE FROM visits WHERE last_visit < ?1", [.real(now.addingTimeInterval(-Self.retention).timeIntervalSince1970)])
    }

    /// Number of entries in a profile.
    public func count(profileID: UUID) -> Int {
        lock.withLock {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT count(*) FROM visits WHERE profile = ?1", -1, &statement, nil) == SQLITE_OK else {
                return 0
            }
            Value.text(profileID.uuidString).bind(statement, 1)
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    // MARK: SQLite plumbing

    enum Value {
        case text(String)
        case real(Double)
        case int(Int)
        case null

        func bind(_ statement: OpaquePointer?, _ index: Int32) {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            switch self {
            case .text(let s): sqlite3_bind_text(statement, index, s, -1, transient)
            case .real(let d): sqlite3_bind_double(statement, index, d)
            case .int(let i): sqlite3_bind_int64(statement, index, Int64(i))
            case .null: sqlite3_bind_null(statement, index)
            }
        }
    }

    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    private func exec(_ sql: String) throws {
        try lock.withLock {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "exec failed"
                sqlite3_free(error)
                throw HistoryError.sqlite(message)
            }
        }
    }

    private func run(_ sql: String, _ args: [Value]) {
        lock.withLock {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            for (i, arg) in args.enumerated() { arg.bind(statement, Int32(i + 1)) }
            _ = sqlite3_step(statement)
        }
    }

    private func query(_ sql: String, _ args: [Value]) -> [HistoryEntry] {
        lock.withLock {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            for (i, arg) in args.enumerated() { arg.bind(statement, Int32(i + 1)) }
            var out: [HistoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let raw = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: raw)) else { continue }
                let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                out.append(
                    HistoryEntry(
                        url: url, title: title, lastVisit: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        visitCount: Int(sqlite3_column_int64(statement, 3))))
            }
            return out
        }
    }
}

/// History store failures.
public enum HistoryError: Error, Equatable {
    /// SQLite reported an error.
    case sqlite(String)
}
