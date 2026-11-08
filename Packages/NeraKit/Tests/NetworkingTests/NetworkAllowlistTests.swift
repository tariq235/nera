// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Networking

/// SEC-063: Nera's own requests may reach only allowlisted HTTPS hosts, checked at runtime.
@Suite("Runtime network allowlist")
struct NetworkAllowlistTests {
    let allowlist = NetworkAllowlist(hosts: ["updates.nera.example", ".cdn.nera.example"])

    @Test func onlyAllowlistedHTTPSHostsPass() {
        #expect(allowlist.allows(URL(string: "https://updates.nera.example/feed.xml")!))
        #expect(allowlist.allows(URL(string: "https://eu.cdn.nera.example/x")!), "subdomain of a dot-entry")
        #expect(!allowlist.allows(URL(string: "http://updates.nera.example/feed.xml")!), "HTTPS only")
        #expect(!allowlist.allows(URL(string: "https://tracker.example/pixel")!))
        #expect(!allowlist.allows(URL(string: "https://updates.nera.example.evil.example/")!), "no suffix tricks")
        #expect(!allowlist.allows(URL(string: "https://cdn.nera.example.evil/")!))
        #expect(!allowlist.allows(URL(string: "file:///etc/hosts")!))
    }

    @Test func nerasOwnAllowlistHoldsOnlyTheUpdateExtensionAndSafeBrowsingHosts() {
        #expect(
            NetworkAllowlist.nera.hosts == [
                "api.github.com", "clients2.google.com", "clients2.googleusercontent.com", "github.com",
                "release-assets.githubusercontent.com", "objects.githubusercontent.com", "safebrowsing.googleapis.com",
            ], "update feed and downloads (ADR-0011), extensions, Safe Browsing; nothing else")
        #expect(NetworkAllowlist.nera.allows(URL(string: "https://github.com/tariq235/nera/releases/latest/download/appcast.xml")!))
        #expect(!NetworkAllowlist.nera.allows(URL(string: "http://github.com/")!), "HTTPS only")
        #expect(!NetworkAllowlist.nera.allows(URL(string: "https://duckduckgo.com/")!))
    }

    @Test func refusedRequestsFailBeforeConnecting() async {
        let client = NeraHTTPClient(allowlist: allowlist)
        await #expect(throws: NetworkPolicyError.hostNotAllowed("tracker.example")) {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://tracker.example/pixel")!))
        }
    }

    @Test func redirectsToUnlistedHostsAreRefused() async {
        let client = NeraHTTPClient(allowlist: allowlist)
        let response = HTTPURLResponse(
            url: URL(string: "https://updates.nera.example/")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let task = URLSession.shared.dataTask(with: URL(string: "https://updates.nera.example/")!)
        let evil = await client.urlSession(
            .shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://tracker.example/")!)
        )
        let fine = await client.urlSession(
            .shared, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://updates.nera.example/v2")!))
        #expect(evil == nil)
        #expect(fine?.url?.host() == "updates.nera.example")
    }
}
