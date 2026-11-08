// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Storage

/// Browsing history.
@Suite("History store")
struct HistoryStoreTests {
    let me = UUID()
    let work = UUID()
    let day: TimeInterval = 86_400
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    func store() throws -> HistoryStore { try HistoryStore(fileURL: nil) }
    func url(_ s: String) -> URL { URL(string: s)! }

    @Test func visitsAreCountedAndTitlesKept() throws {
        let h = try store()
        h.recordVisit(url("https://a.example/"), title: "A", profileID: me, at: now)
        h.recordVisit(url("https://a.example/"), title: nil, profileID: me, at: now + 60)
        h.updateTitle(url("https://a.example/"), title: "A — renamed", profileID: me)
        let entry = try #require(h.recent(profileID: me).first)
        #expect(entry.visitCount == 2 && entry.title == "A — renamed" && entry.lastVisit == now + 60)
    }

    @Test func onlyWebPagesAreRecordedAndProfilesAreSeparate() throws {
        let h = try store()
        for raw in ["about:blank", "data:text/html,x", "file:///etc/hosts", "blob:https://a.example/1"] {
            h.recordVisit(url(raw), title: "x", profileID: me, at: now)
        }
        h.recordVisit(url("https://work.example/"), title: "Work", profileID: work, at: now)
        #expect(h.count(profileID: me) == 0)
        #expect(h.recent(profileID: work).map(\.title) == ["Work"])
    }

    @Test func searchMatchesEveryWordAndRanksByFrecency() throws {
        let h = try store()
        h.recordVisit(url("https://docs.swift.org/concurrency"), title: "Concurrency", profileID: me, at: now - 30 * day)
        for i in 0..<5 { h.recordVisit(url("https://swift.org/blog"), title: "Swift Blog", profileID: me, at: now - Double(i) * 60) }
        h.recordVisit(url("https://news.example/swift"), title: "Swift news", profileID: me, at: now - 2 * day)
        #expect(h.search("swift", profileID: me, now: now).map(\.url.host) == ["swift.org", "news.example", "docs.swift.org"])
        #expect(h.search("swift blog", profileID: me, now: now).map(\.title) == ["Swift Blog"], "every word must match")
        #expect(h.search("100%_off", profileID: me, now: now).isEmpty, "LIKE wildcards are escaped")
        #expect(h.search("SWIFT NEWS", profileID: me, now: now).count == 1, "case-insensitive")
    }

    @Test func clearingByRangeAndPruning() throws {
        let h = try store()
        h.recordVisit(url("https://old.example/"), title: "Old", profileID: me, at: now - 100 * day)
        h.recordVisit(url("https://week.example/"), title: "Week", profileID: me, at: now - 5 * day)
        h.recordVisit(url("https://hour.example/"), title: "Hour", profileID: me, at: now - 600)
        h.recordVisit(url("https://work.example/"), title: "Work", profileID: work, at: now - 600)
        h.clear(profileID: me, since: now - 3600)
        #expect(h.recent(profileID: me).map(\.title) == ["Week", "Old"], "last hour cleared")
        #expect(h.count(profileID: work) == 1, "other profiles untouched")
        h.prune(now: now)
        #expect(h.recent(profileID: me).map(\.title) == ["Week"], "older than 90 days dropped")
        h.delete(url("https://week.example/"), profileID: me)
        h.clear(profileID: work)
        #expect(h.count(profileID: me) == 0 && h.count(profileID: work) == 0)
    }

    @Test func historySurvivesReopeningTheFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "nera-history-\(UUID().uuidString).sqlite")
        try HistoryStore(fileURL: file).recordVisit(url("https://kept.example/"), title: "Kept", profileID: me, at: now)
        #expect(try HistoryStore(fileURL: file).recent(profileID: me).map(\.title) == ["Kept"])
    }
}

extension HistoryStoreTests {
    @Test func importMergesWithExistingHistory() throws {
        let h = try store()
        h.recordVisit(url("https://a.example/"), title: "A", profileID: me, at: now)
        let added = h.importVisits(
            [
                HistoryEntry(url: url("https://a.example/"), title: "A from Chrome", lastVisit: now - day, visitCount: 9),
                HistoryEntry(url: url("https://b.example/"), title: "B", lastVisit: now - 2 * day, visitCount: 1),
                HistoryEntry(url: url("chrome://flags"), title: "Flags", lastVisit: now, visitCount: 1),
            ], profileID: me)
        #expect(added == 2, "non-web pages are skipped")
        let a = try #require(h.recent(profileID: me).first { $0.url.host == "a.example" })
        #expect(a.visitCount == 9 && a.lastVisit == now && a.title == "A", "keeps the larger count, later time, existing title")
    }

    @Test func topSitesAreOnePerHostMostUsedFirst() throws {
        let h = try store()
        for _ in 0..<3 { h.recordVisit(url("https://b.example/x"), title: "B", profileID: me, at: now) }
        h.recordVisit(url("https://b.example/y"), title: "B2", profileID: me, at: now)
        h.recordVisit(url("https://a.example/"), title: "A", profileID: me, at: now)
        h.recordVisit(url("https://c.example/"), title: "C", profileID: work, at: now)
        let top = h.topSites(profileID: me, limit: 8, now: now)
        #expect(top.map { $0.url.host() } == ["b.example", "a.example"], "one per host, other profiles excluded")
    }
}
