// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import SecurityPolicy

/// Web-security conformance: the same cases on every engine, against ``LocalTestServer`` (no external
/// sites). Engines must trust the server's test CA in Debug test runs for the cases that need a valid
/// certificate (S04, S05). Cases are part of ``EngineConformance/cases`` and appear in the parity matrix.
public enum SecurityConformance {
    /// Non-loopback name Chromium maps to the test server in Debug test runs (see S05).
    public static let chromiumInsecureHost = "mixed.nera.test"

    /// The server, or a failure explaining why the security cases can't run.
    static func server() throws -> LocalTestServer {
        guard let server = LocalTestServer.shared else { throw ConformanceFailure("local test server didn't start") }
        return server
    }

    /// A bad certificate never shows the page: the engine reports a certificate failure or asks for a decision.
    @MainActor
    static func rejects(_ mode: LocalTestServer.TLSMode, _ ctx: ConformanceContext) async throws {
        let server = try server()
        let (page, rec) = ctx.makePage()
        rec.keepRequests = true
        page.load(server.url("/page?title=SHOULD-NOT-LOAD", tls: mode))
        try await ctx.wait("certificate failure") {
            rec.requests.contains { if case .certificateError = $0 { true } else { false } }
                || rec.events.contains { if case .navigationFailed = $0 { true } else { false } }
        }
        try await Task.sleep(for: .milliseconds(300))
        try ctx.expect(page.state.title != "SHOULD-NOT-LOAD", "page with a \(mode.rawValue) certificate was shown")
    }

    /// Every security case, in matrix order.
    public static let cases: [ConformanceCase] = [
        ConformanceCase(id: "S01", title: "Expired certificate: page never shown", requires: []) { try await rejects(.expired, $0) },
        ConformanceCase(id: "S02", title: "Certificate for another host: page never shown", requires: []) {
            try await rejects(.wrongHost, $0)
        },
        ConformanceCase(id: "S03", title: "Self-signed certificate: page never shown", requires: []) { try await rejects(.selfSigned, $0) },
        ConformanceCase(id: "S04", title: "Valid certificate loads (test CA trusted in Debug test runs only)", requires: []) { ctx in
            let server = try server()
            let (page, _) = ctx.makePage()
            page.load(server.url("/page?title=SECURE", tls: .valid))
            try await ctx.wait("secure page") { page.state.title == "SECURE" }
        },
        ConformanceCase(id: "S05", title: "Mixed active content (HTTP script on an HTTPS page) is blocked", requires: []) { ctx in
            let server = try server()
            let (page, _) = ctx.makePage()
            // Chromium treats http://127.0.0.1 as potentially trustworthy (not "mixed"), so it loads the insecure
            // script from a non-loopback name mapped to the server by a Debug-only resolver rule.
            let host = ctx.engine.descriptor.id == "chromium" ? SecurityConformance.chromiumInsecureHost : "127.0.0.1"
            page.load(server.url("/mixed?host=\(host)", tls: .valid))
            try await ctx.wait("mixed verdict") { page.state.title == "MIXED BLOCKED" || page.state.title == "MIXED RAN" }
            try ctx.expect(page.state.title == "MIXED BLOCKED", "insecure script ran on a secure page")
        },
        ConformanceCase(id: "S06", title: "Content-Security-Policy blocks inline script, allows same-origin script", requires: []) { ctx in
            let server = try server()
            let (page, _) = ctx.makePage()
            page.load(server.url("/csp"))
            try await ctx.wait("CSP verdict") { page.state.title == "CSP OK" || page.state.title == "INLINE RAN" }
            try ctx.expect(page.state.title == "CSP OK", "inline script ran despite CSP")
        },
        ConformanceCase(id: "S07", title: "X-Content-Type-Options: nosniff — text/plain is never run as script", requires: []) { ctx in
            let server = try server()
            let (page, _) = ctx.makePage()
            page.load(server.url("/nosniff"))
            try await ctx.wait("nosniff verdict") { page.state.title == "NOSNIFF OK" || page.state.title == "SNIFFED" }
            try ctx.expect(page.state.title == "NOSNIFF OK", "a nosniff text/plain response ran as script")
        },
        ConformanceCase(id: "S08", title: "SameSite=Lax cookies aren't sent on cross-site subresource requests", requires: []) { ctx in
            let server = try server()
            let session = UUID()
            let (a, _) = ctx.makePage(storage: .ephemeral(session))
            a.load(server.url("/setcookie?v=lax1&samesite=Lax"))
            try await ctx.wait("cookie set") { a.state.title == "SET lax1" }
            let before = server.requests("/pixel").count
            let (b, _) = ctx.makePage(storage: .ephemeral(session))
            let target = server.url("/pixel").absoluteString
            b.load(
                server.url("/xsite?target=\(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")", host: "localhost"))
            try await ctx.wait("cross-site image") { server.requests("/pixel").count > before || b.state.title == "XSITE DONE" }
            try await Task.sleep(for: .milliseconds(200))
            let sent = server.requests("/pixel").dropFirst(before).compactMap(\.cookie).joined()
            try ctx.expect(!sent.contains("lax1"), "a SameSite=Lax cookie was sent cross-site: \(sent)")
        },
        ConformanceCase(id: "S09", title: "Popups opened by script without a user gesture are blocked", requires: []) { ctx in
            let server = try server()
            let (page, rec) = ctx.makePage()
            page.load(server.url("/popup"))
            try await ctx.wait("popup page") { page.state.title == "POPUP" }
            try await Task.sleep(for: .milliseconds(700))
            let opened = rec.requests.contains { if case .newPage = $0 { true } else { false } }
            try ctx.expect(!opened, "a script-opened window was created without a user gesture")
        },
        ConformanceCase(id: "S10", title: "A server redirect to file: is blocked", requires: []) { ctx in
            let server = try server()
            let (page, _) = ctx.makePage()
            page.load(server.url("/redirect?to=file:///etc/hosts"))
            try await Task.sleep(for: .seconds(1.5))
            try ctx.expect(page.state.url?.scheme != "file", "redirected into the local file system")
        },
        ConformanceCase(id: "S11", title: "Profiles don't share cookies", requires: []) { ctx in
            let server = try server()
            let profileA = UUID()
            let (a, _) = ctx.makePage(storage: .persistent(profileA))
            a.load(server.url("/setcookie?v=profileA"))
            try await ctx.wait("cookie set in A") { a.state.title == "SET profileA" }
            let (b, _) = ctx.makePage(storage: .persistent(UUID()))
            b.load(server.url("/cookies"))
            try await ctx.wait("B's cookies") { b.state.title.hasPrefix("COOKIES") }
            try ctx.expect(!b.state.title.contains("profileA"), "profile B saw profile A's cookie")
            let (a2, _) = ctx.makePage(storage: .persistent(profileA))
            a2.load(server.url("/cookies"))
            try await ctx.wait("A's cookies") { a2.state.title.hasPrefix("COOKIES") }
            try ctx.expect(a2.state.title.contains("profileA"), "profile A lost its own cookie: \(a2.state.title)")
        },
        ConformanceCase(id: "S12", title: "Profiles don't share local storage", requires: []) { ctx in
            let server = try server()
            let profileA = UUID()
            let (a, _) = ctx.makePage(storage: .persistent(profileA))
            a.load(server.url("/storage?set=fromA"))
            try await ctx.wait("A stored") { a.state.title == "STORAGE fromA" }
            let (b, _) = ctx.makePage(storage: .persistent(UUID()))
            b.load(server.url("/storage"))
            // "STORAGE <value>" is the script's title; plain "STORAGE" is the page's own, before the script ran.
            try await ctx.wait("B read") { b.state.title.hasPrefix("STORAGE ") }
            try ctx.expect(b.state.title == "STORAGE none", "profile B read A's storage: \(b.state.title)")
        },
        ConformanceCase(id: "S13", title: "Profiles don't share the HTTP cache", requires: []) { ctx in
            let server = try server()
            let profileA = UUID()
            let start = server.requests("/cacheable").count
            for _ in 0..<2 {
                let (a, _) = ctx.makePage(storage: .persistent(profileA))
                a.load(server.url("/cacheable"))
                try await ctx.wait("A cached page") { a.state.title == "CACHE" }
            }
            let afterA = server.requests("/cacheable").count
            let (b, _) = ctx.makePage(storage: .persistent(UUID()))
            b.load(server.url("/cacheable"))
            try await ctx.wait("B page") { b.state.title == "CACHE" }
            try ctx.expect(afterA - start <= 2, "sanity: at most one request per page in A")
            try ctx.expect(server.requests("/cacheable").count > afterA, "profile B was served from profile A's cache")
        },
        ConformanceCase(id: "S14", title: "Private sessions leave nothing behind and never see profile or other-session data", requires: [])
        {
            ctx in
            let server = try server()
            let first = UUID()
            let (p, _) = ctx.makePage(storage: .ephemeral(first))
            p.load(server.url("/setcookie?v=private1"))
            try await ctx.wait("cookie set privately") { p.state.title == "SET private1" }
            p.close()
            let (next, _) = ctx.makePage(storage: .ephemeral(UUID()))
            next.load(server.url("/cookies"))
            try await ctx.wait("next private session") { next.state.title.hasPrefix("COOKIES") }
            try ctx.expect(!next.state.title.contains("private1"), "a new private session saw an old one's cookie")
            let (profile, _) = ctx.makePage(storage: .persistent(UUID()))
            profile.load(server.url("/cookies"))
            try await ctx.wait("profile") { profile.state.title.hasPrefix("COOKIES") }
            try ctx.expect(!profile.state.title.contains("private1"), "a profile saw a private session's cookie")
        },
    ]
}
