// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Which engine shows a site. Nera's Chromium can't play H.264/AAC video or DRM-protected streams (standard CEF has
/// neither: proprietary codecs need a licensed build, Widevine a license from Google); WebKit plays both. So
/// streaming services open in WebKit by default, and the user can send any other site there too.
public enum SiteEngines {
    /// Streaming services that need DRM or H.264/AAC: WebKit by default.
    public static let webKitByDefault: Set<String> = [
        "netflix.com", "disneyplus.com", "primevideo.com", "hulu.com", "max.com", "tv.apple.com", "peacocktv.com",
        "paramountplus.com", "crunchyroll.com", "open.spotify.com", "music.apple.com", "music.amazon.com", "tidal.com",
        "deezer.com",
    ]

    /// The key sites are stored under: the host without "www.".
    public static func site(of url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty, ["http", "https"].contains(url?.scheme ?? "") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The engine `url` should use in `profile`, if the site has a preference: the user's choice for the site or a
    /// parent domain first, then the built-in streaming list. Nil: the profile's engine.
    public static func preferred(for url: URL?, in profile: Profile) -> EngineID? {
        guard let site = site(of: url) else { return nil }
        let candidates = ancestors(of: site)
        if let choices = profile.siteEngines {
            for candidate in candidates { if let engine = choices[candidate] { return engine } }
        }
        return candidates.contains(where: webKitByDefault.contains) ? .webKit : nil
    }

    /// `a.b.example.com` → [`a.b.example.com`, `b.example.com`, `example.com`].
    static func ancestors(of site: String) -> [String] {
        let labels = site.split(separator: ".")
        guard labels.count > 1 else { return [site] }
        return (0..<(labels.count - 1)).map { labels[$0...].joined(separator: ".") }
    }

    /// The registrable part of a host, roughly ("open.spotify.com" → "spotify.com"; a few two-part suffixes such
    /// as "co.uk" are known).
    public static func registrableDomain(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count > 2 else { return host.lowercased() }
        let twoPart: Set = ["co.uk", "com.au", "co.jp", "co.in", "com.br", "co.nz", "com.sg"]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return twoPart.contains(lastTwo) ? labels.suffix(3).joined(separator: ".") : lastTwo
    }

    /// Whose cookies go with a tab moving to `url`'s engine: its registrable domain (a sign-in on
    /// accounts.spotify.com is a cookie on spotify.com). `nil` for non-web URLs and IP addresses.
    public static func cookieSite(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = url.host()?.lowercased(),
            !host.isEmpty, host.rangeOfCharacter(from: CharacterSet.letters) != nil
        else { return nil }
        return registrableDomain(host)
    }
}
