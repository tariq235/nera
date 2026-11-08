// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// The origin (scheme, host, port) that a page request comes from. Shown to the user on every
/// permission prompt and dialog, so a page can't impersonate another site or the browser (SR-041).
public struct SecurityOrigin: Hashable, Sendable, CustomStringConvertible {
    /// Lower-cased scheme, e.g. `https`. Empty for opaque origins.
    public var scheme: String
    /// Lower-cased host. Empty for opaque origins.
    public var host: String
    /// Explicit port, if it isn't the scheme's default.
    public var port: Int?

    /// Creates an origin from parts. Default ports (80 for http, 443 for https) are dropped.
    public init(scheme: String, host: String, port: Int?) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        let defaultPort = ["http": 80, "https": 443][self.scheme]
        self.port = port == defaultPort ? nil : port
    }

    /// The origin of `url`. `data:`, `about:`, `blob:` without a host and missing URLs give ``opaque``.
    public init(url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: true), !host.isEmpty else {
            self = .opaque
            return
        }
        self.init(scheme: scheme, host: host, port: url.port)
    }

    /// An origin with no identity (e.g. a `data:` page). Displayed as "This page".
    public static let opaque = SecurityOrigin(scheme: "", host: "", port: nil)

    /// `true` for origins without a scheme and host.
    public var isOpaque: Bool { scheme.isEmpty && host.isEmpty }

    /// `true` for `https` origins and loopback hosts.
    public var isSecure: Bool { scheme == "https" || NavigationPolicy.isLoopback(host) }

    /// User-facing form: `https://example.com`, `http://localhost:3000`, or "This page".
    public var description: String {
        if isOpaque { return "This page" }
        return "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }
}
