// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
public import Foundation

/// A URL as Safe Browsing sees it (v5 "URLs and Hashing"): canonicalized, then turned into the host-suffix /
/// path-prefix expressions whose SHA-256 hashes are looked up. Works on bytes, like the specification.
public struct SafeBrowsingURL: Equatable, Sendable {
    /// `http` or `https` (anything else isn't checked).
    public let scheme: String
    /// Canonical host: lowercase, no stray dots, IPv4 in dotted decimal, escaped.
    public let host: String
    /// Canonical path, starting with `/`.
    public let path: String
    /// The query without `?`, or nil when the URL has no `?`.
    public let query: String?

    /// The canonical URL (the port and user info are dropped).
    public var canonical: String { "\(scheme)://\(host)\(path)\(query.map { "?\($0)" } ?? "")" }

    /// Canonicalizes `string`; nil for URLs Safe Browsing doesn't cover (not http/https, or no host).
    public init?(_ string: String) {
        // Leading and trailing spaces; tab, CR and LF anywhere; the fragment.
        var text = string.trimmingCharacters(in: .whitespaces)
        text.removeAll { $0 == "\t" || $0 == "\r" || $0 == "\n" }
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        if !text.contains("://") { text = "http://" + text }
        guard let colon = text.range(of: "://") else { return nil }
        let scheme = text[..<colon.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        let rest = text[colon.upperBound...]
        let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        var authority = String(rest[..<authorityEnd])
        var pathAndQuery = String(rest[authorityEnd...])
        if pathAndQuery.isEmpty || pathAndQuery.hasPrefix("?") { pathAndQuery = "/" + pathAndQuery }
        if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
        if !authority.hasSuffix("]"), let portColon = authority.lastIndex(of: ":"),
            authority[authority.index(after: portColon)...].allSatisfy(\.isNumber)
        {
            authority = String(authority[..<portColon])
        }
        guard let host = Self.canonicalHost(authority) else { return nil }
        let pathPart: String
        let queryPart: String?
        if let q = pathAndQuery.firstIndex(of: "?") {
            pathPart = String(pathAndQuery[..<q])
            queryPart = String(pathAndQuery[pathAndQuery.index(after: q)...])
        } else {
            pathPart = pathAndQuery
            queryPart = nil
        }
        self.scheme = scheme
        self.host = host
        self.path = Self.escape(Self.canonicalPath(Self.unescape(Array(pathPart.utf8))))
        self.query = queryPart.map { Self.escape(Self.unescape(Array($0.utf8))) }
    }

    // MARK: Expressions

    /// The host-suffix / path-prefix expressions to look up, most specific first (at most 30): the exact host and
    /// up to four suffixes from its last five components (none for IP addresses), times the path with and without
    /// its query and up to four directory prefixes from the root.
    public var expressions: [String] {
        var hosts = [host]
        if !Self.isIPv4(host), !host.hasPrefix("[") {
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            // Suffixes of the last two to five components, longest first.
            for count in stride(from: min(5, parts.count), through: 2, by: -1) {
                let suffix = parts.suffix(count).joined(separator: ".")
                if suffix != host { hosts.append(suffix) }
            }
        }
        var paths: [String] = []
        if let query { paths.append(path + "?" + query) }
        paths.append(path)
        var prefix = ""
        let directories = path.split(separator: "/", omittingEmptySubsequences: true).dropLast(path.hasSuffix("/") ? 0 : 1)
        var prefixes = ["/"]
        prefix = "/"
        for directory in directories.prefix(3) {
            prefix += directory + "/"
            prefixes.append(prefix)
        }
        for p in prefixes where !paths.contains(p) { paths.append(p) }
        var out: [String] = []
        for h in hosts {
            for p in paths where !out.contains(h + p) { out.append(h + p) }
        }
        return Array(out.prefix(30))
    }

    /// SHA-256 of each expression (32 bytes).
    public var fullHashes: [Data] { expressions.map { Data(SHA256.hash(data: Data($0.utf8))) } }

    // MARK: Host

    static func canonicalHost(_ raw: String) -> String? {
        var bytes = unescape(Array(raw.utf8))
        if bytes.first == UInt8(ascii: "["), bytes.last == UInt8(ascii: "]") {
            return escape(Array(String(decoding: bytes, as: UTF8.self).lowercased().utf8))
        }
        while bytes.first == UInt8(ascii: ".") { bytes.removeFirst() }
        while bytes.last == UInt8(ascii: ".") { bytes.removeLast() }
        var collapsed: [UInt8] = []
        for b in bytes where !(b == UInt8(ascii: ".") && collapsed.last == UInt8(ascii: ".")) { collapsed.append(b) }
        guard !collapsed.isEmpty else { return nil }
        let lowered = collapsed.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        let text = String(decoding: lowered, as: UTF8.self)
        if let ip = ipv4(text) { return ip }
        return escape(lowered)
    }

    /// Any legal IPv4 form (decimal, octal `0…`, hex `0x…`, one to four parts) in dotted decimal, or nil.
    static func ipv4(_ host: String) -> String? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var values: [UInt64] = []
        for part in parts {
            let p = part.lowercased()
            let value: UInt64?
            if p.hasPrefix("0x") {
                value = p.count == 2 ? 0 : UInt64(p.dropFirst(2), radix: 16)
            } else if p.count > 1, p.hasPrefix("0") {
                value = UInt64(p.dropFirst(), radix: 8)
            } else {
                value = p.isEmpty ? nil : UInt64(p, radix: 10)
            }
            guard let value else { return nil }
            values.append(value)
        }
        // The last part fills the remaining bytes; the others are one byte each.
        let leading = values.dropLast()
        guard leading.allSatisfy({ $0 <= 255 }), let last = values.last, last < (UInt64(1) << (8 * (5 - values.count))) else { return nil }
        var address: UInt64 = 0
        for (i, v) in leading.enumerated() { address |= v << (8 * (3 - i)) }
        address |= last
        return (0..<4).map { String((address >> (8 * (3 - $0))) & 0xFF) }.joined(separator: ".")
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    // MARK: Path and escaping

    /// Resolves `/./` and `/../` and collapses runs of slashes, byte for byte (the path may not be valid UTF-8).
    static func canonicalPath(_ bytes: [UInt8]) -> [UInt8] {
        let slash = UInt8(ascii: "/")
        let dot = UInt8(ascii: ".")
        let segments = bytes.split(separator: slash, omittingEmptySubsequences: true)
        let last = segments.last.map(Array.init)
        let trailingSlash = bytes.last == slash || last == [dot] || last == [dot, dot]
        var kept: [ArraySlice<UInt8>] = []
        for segment in segments {
            if segment.elementsEqual([dot]) { continue }
            if segment.elementsEqual([dot, dot]) {
                _ = kept.popLast()
                continue
            }
            kept.append(segment)
        }
        var path: [UInt8] = [slash]
        for (i, segment) in kept.enumerated() {
            if i > 0 { path.append(slash) }
            path += segment
        }
        if trailingSlash, path.last != slash { path.append(slash) }
        return path
    }

    /// Percent-decodes until nothing changes (the result may not be valid UTF-8).
    static func unescape(_ input: [UInt8]) -> [UInt8] {
        var bytes = input
        while true {
            var out: [UInt8] = []
            out.reserveCapacity(bytes.count)
            var i = 0
            var changed = false
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "%"), i + 2 < bytes.count, let hi = hexValue(bytes[i + 1]), let lo = hexValue(bytes[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                    changed = true
                } else {
                    out.append(bytes[i])
                    i += 1
                }
            }
            if !changed { return out }
            bytes = out
        }
    }

    /// Escapes bytes ≤ 32, ≥ 127, `#` and `%` as `%XX` (uppercase).
    static func escape(_ bytes: [UInt8]) -> String {
        var out = ""
        for b in bytes {
            if b <= 32 || b >= 127 || b == UInt8(ascii: "#") || b == UInt8(ascii: "%") {
                out += String(format: "%%%02X", b)
            } else {
                out.unicodeScalars.append(UnicodeScalar(b))
            }
        }
        return out
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
