// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import Networking

/// v0.1 update check: the latest GitHub release of the public repo (the in-app installer comes with Sparkle's
/// installer, ADR-0011). Contacts only `api.github.com`, at most once a day, and the user can turn it off.
public enum ReleaseCheck {
    /// A newer release.
    public struct Release: Equatable, Sendable {
        /// Version, e.g. "0.2.0".
        public var version: String
        /// The release page.
        public var url: URL
    }

    /// The repository releases come from.
    public static let repository = "tariq235/nera"

    /// The latest release if it's newer than `currentVersion`; nil otherwise or on any error.
    public static func newerRelease(than currentVersion: String, client: NeraHTTPClient = NeraHTTPClient()) async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await client.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return parse(data, currentVersion: currentVersion)
    }

    /// The release in a GitHub API response, if it's a newer, non-draft, non-prerelease version.
    public static func parse(_ data: Data, currentVersion: String) -> Release? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let tag = json["tag_name"] as? String, json["draft"] as? Bool != true,
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)), page.host() == "github.com"
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(version, than: currentVersion) ? Release(version: version, url: page) : nil
    }

    /// Numeric comparison of dotted versions ("0.10.0" > "0.9.3"); pre-release suffixes are ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l > r }
        }
        return false
    }
}
