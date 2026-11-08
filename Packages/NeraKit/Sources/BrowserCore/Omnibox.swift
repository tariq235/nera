// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Decides whether command-bar input is a URL to open or a search query.
public enum Omnibox {
    /// What the input means.
    public enum Result: Equatable, Sendable {
        /// Open this URL directly.
        case url(URL)
        /// Search for `query` at `url`.
        case search(query: String, url: URL)

        /// The URL to load in either case.
        public var url: URL {
            switch self {
            case .url(let u), .search(_, let u): u
            }
        }
    }

    /// Schemes passed through as typed. Everything is still checked by `SecurityKit.NavigationPolicy`.
    static let passthroughSchemes: Set<String> = ["http", "https", "about", "file", "data", "view-source", "mailto", "javascript", "blob"]

    /// Classifies command-bar input. Returns `nil` for blank input. Navigation safety is *not*
    /// decided here: `SecurityPolicy.NavigationPolicy` checks the resulting URL.
    public static func parse(_ raw: String, engine: SearchEngine) -> Result? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let scheme = explicitScheme(input), passthroughSchemes.contains(scheme), let url = URL(string: input) {
            return .url(url)
        }
        if !input.contains(where: \.isWhitespace), looksLikeHost(input), let url = URL(string: "https://" + input), url.host() != nil {
            if isLocal(input), let local = URL(string: "http://" + input) { return .url(local) }
            return .url(url)
        }
        return engine.url(for: input).map { .search(query: input, url: $0) }
    }

    private static func explicitScheme(_ s: String) -> String? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let scheme = s[..<colon].lowercased()
        guard let first = scheme.first, first.isLetter,
            scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) })
        else { return nil }
        return scheme
    }

    private static func hostPart(_ s: String) -> Substring {
        let end = s.firstIndex { "/?#".contains($0) } ?? s.endIndex
        let hostPort = s[..<end]
        if let colon = hostPort.lastIndex(of: ":"), hostPort[hostPort.index(after: colon)...].allSatisfy(\.isNumber) {
            return hostPort[..<colon]
        }
        return hostPort
    }

    private static func isLocal(_ s: String) -> Bool {
        let host = hostPart(s).lowercased()
        return host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1"
    }

    private static func looksLikeHost(_ s: String) -> Bool {
        let host = hostPart(s).lowercased()
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 4, labels.allSatisfy({ UInt8($0) != nil }) { return true }  // IPv4
        guard labels.count >= 2, let tld = labels.last, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let validLabel: (Substring) -> Bool = { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
        guard labels.allSatisfy(validLabel) else { return false }
        return (tld.count >= 2 && tld.allSatisfy(\.isLetter)) || tld.hasPrefix("xn--")
    }
}
