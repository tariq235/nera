// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Inline completion in the command bar: the site the typed text starts ("you" → "youtube.com").
public enum SiteCompletion {
    /// The first site among `candidates` (most relevant first: history, open tabs) whose address starts with
    /// `typed`, without "www.". Nil for an empty query, a search with spaces, or no match.
    public static func complete(_ typed: String, candidates: [URL]) -> String? {
        let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, !query.contains(" "), !query.contains("/") else { return nil }
        for url in candidates {
            guard let host = site(of: url), host.hasPrefix(query), host != query else { continue }
            return host
        }
        return nil
    }

    /// A URL's site as shown and completed: its host without "www.".
    public static func site(of url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty, ["http", "https"].contains(url.scheme ?? "") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
