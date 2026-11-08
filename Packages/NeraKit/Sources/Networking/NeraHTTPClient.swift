// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// The hosts Nera itself may contact (not sites the user visits — those go through the engines and the
/// navigation policy). Every entry must also appear in the network inventory in
/// docs/security/security-model.md; CI checks both lists match (`scripts/ci/check-network-inventory.sh`).
public struct NetworkAllowlist: Sendable, Equatable {
    /// Exact host names. A leading `.` allows that domain's subdomains (`.example.com` → `a.example.com`).
    public let hosts: Set<String>

    /// Creates an allowlist.
    public init(hosts: Set<String>) { self.hosts = Set(hosts.map { $0.lowercased() }) }

    /// Nera's own allowlist: the daily update check (GitHub releases) and extension downloads from the Chrome
    /// Web Store (user-initiated). Entries are added here and to the inventory together.
    public static let nera = NetworkAllowlist(hosts: [
        "api.github.com", "clients2.google.com", "clients2.googleusercontent.com", "github.com", "release-assets.githubusercontent.com",
        "objects.githubusercontent.com", "safebrowsing.googleapis.com",
    ])

    /// Whether Nera may send `url`: HTTPS only, and only to an allowlisted host.
    public func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        if hosts.contains(host) { return true }
        return hosts.contains { $0.hasPrefix(".") && host.hasSuffix($0) }
    }
}

/// Why a request was refused.
public enum NetworkPolicyError: Error, Equatable, Sendable {
    /// The host (or redirect target) isn't on the allowlist, or the URL isn't HTTPS.
    case hostNotAllowed(String)
}

/// The only HTTP client Nera's own code may use (the architecture check forbids URLSession elsewhere).
/// Requests and redirects to hosts outside the allowlist fail before any connection is made (SEC-063).
/// No cookies, cache or credentials are shared with the engines: an ephemeral session.
public final class NeraHTTPClient: NSObject, Sendable, URLSessionTaskDelegate {
    /// The hosts this client may contact.
    public let allowlist: NetworkAllowlist
    private let session: URLSession

    /// Creates a client.
    public init(allowlist: NetworkAllowlist = .nera) {
        self.allowlist = allowlist
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: configuration)
        super.init()
    }

    /// Sends a request after checking the allowlist (also checked again for every redirect).
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, allowlist.allows(url) else {
            throw NetworkPolicyError.hostNotAllowed(request.url?.host() ?? "?")
        }
        return try await session.data(for: request, delegate: self)
    }

    /// Redirects are checked like the original request; a refused redirect stops the request.
    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, allowlist.allows(url) else { return nil }
        return request
    }
}
