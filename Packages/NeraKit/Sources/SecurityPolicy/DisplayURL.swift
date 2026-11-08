// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// How URLs are shown to the user. Showing the real registrable host prominently is the main defense
/// against look-alike phishing domains.
public enum DisplayURL {
    /// Short form for the sidebar/top bar: host without "www.", or a scheme label for non-web URLs.
    public static func short(_ url: URL?) -> String {
        guard let url else { return "" }
        switch url.scheme?.lowercased() {
        case "http", "https":
            guard var host = url.host(percentEncoded: true)?.lowercased() else { return url.absoluteString }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            return host
        case "file": return url.lastPathComponent
        case "data": return "data:"
        case "about": return url.absoluteString
        default: return url.scheme.map { "\($0):" } ?? url.absoluteString
        }
    }

    /// True for http:// pages (shown with a "Not Secure" badge).
    public static func isInsecure(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "http" && !NavigationPolicy.isLoopback(url?.host()?.lowercased() ?? "")
    }
}
