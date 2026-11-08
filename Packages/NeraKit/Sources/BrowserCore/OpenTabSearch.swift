// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Finds open tabs (and Favorites) for the command bar, best first, and tells whether the best one is a strong
/// enough match to put "Switch to Tab" above opening or searching: typing "github" or "github.com" when a GitHub
/// tab is open should take you there, not open a duplicate.
public enum OpenTabSearch {
    /// One match.
    public struct Match: Equatable, Sendable {
        /// The tab.
        public let tab: Tab
        /// The query is the tab's site, or the start of its site or of a word in its title.
        public let isStrong: Bool
    }

    /// Tabs matching `query` (case-insensitive, in their site, address or title), strongest first, at most `limit`.
    public static func matches(_ query: String, in tabs: [Tab], limit: Int = 8) -> [Match] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<UUID>()
        var scored: [(match: Match, rank: Int)] = []  // rank: score first, then sidebar order
        for (order, tab) in tabs.enumerated() {
            guard seen.insert(tab.id).inserted, let score = score(q, tab) else { continue }
            scored.append((Match(tab: tab, isStrong: score >= 3), score * 100_000 - order))
        }
        return scored.sorted { $0.rank > $1.rank }.prefix(limit).map(\.match)
    }

    /// 4: the site itself; 3: the start of the site or of a title word; 2: inside the site or title; 1: in the
    /// address; nil: no match.
    static func score(_ q: String, _ tab: Tab) -> Int? {
        let typedHost =
            q.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map { String($0).replacingOccurrences(of: "www.", with: "") } ?? q
        let host = (tab.url?.host() ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let title = tab.displayTitle.lowercased()
        if !host.isEmpty, host == typedHost { return 4 }
        let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if !host.isEmpty, host.hasPrefix(q) || host.split(separator: ".").contains(where: { $0.hasPrefix(q) }) { return 3 }
        if titleWords.contains(where: { $0.hasPrefix(q) }) { return 3 }
        if host.contains(q) || title.contains(q) { return 2 }
        if tab.url?.absoluteString.lowercased().contains(q) == true { return 1 }
        return nil
    }
}
