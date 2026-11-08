// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
import Foundation
import SecurityPolicy

// Video: a sample Chromium can't play and WebKit can, for case C21 and the app's engine self-test.
extension EngineConformance {
    /// Whether a page's video loaded, and whether `MediaProbe` (EngineKit) flagged it, once one of them happens (8 s at most).
    @MainActor public static func mediaOutcome(_ page: any WebPage) async throws -> (playable: Bool, flagged: Bool) {
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            let playable = await page.evaluate("document.querySelector('video').readyState >= 1") == "true"
            let flagged = await page.evaluate(MediaProbe.script) == MediaProbe.unsupported
            if playable || flagged { return (playable, flagged) }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ConformanceFailure("the video neither loaded nor failed")
    }

    /// Puts a page in a window, as a tab in Nera's window is (WebKit loads no media for a page that isn't in
    /// one), and returns how to close it. Set by the runner (the app's self-test, the WebKit tests): this module
    /// has no UI framework.
    @MainActor public static var showOffscreen: (any WebPage) -> () -> Void = { _ in {} }

    /// The app's self-test: the H.264 sample on a real engine plays (`expectPlayable`) or is flagged for the
    /// other engine. Returns a failure, or nil.
    @MainActor public static func checkVideoSample(on engine: any BrowserEngine, expectPlayable: Bool) async -> String? {
        guard let server = LocalTestServer.shared else { return "local test server didn't start" }
        let recorder = Recorder()
        let page = engine.makePage(
            PageConfiguration(id: UUID(), storage: .ephemeral(UUID()), policy: NavigationPolicy()), delegate: recorder)
        let close = showOffscreen(page)
        defer {
            page.close()
            close()
        }
        page.load(server.url("/video"))
        let outcome = try? await mediaOutcome(page)
        guard let outcome, outcome.playable == expectPlayable, outcome.flagged != expectPlayable else {
            return "H.264 sample: expected \(expectPlayable ? "playable" : "flagged"), got \(String(describing: outcome))"
        }
        return nil
    }

    /// The app's self-test: an engine reads back a site's cookies (and only that site's), for moving tabs between
    /// engines signed in. Returns a failure, or nil.
    @MainActor public static func checkCookiesBySite(on engine: any BrowserEngine) async -> String? {
        let scope = StorageScope.ephemeral(UUID())
        func cookie(_ domain: String, _ name: String) -> WebCookie {
            WebCookie(
                domain: domain, name: name, value: "v", path: "/", expires: Date().addingTimeInterval(3600), isSecure: true,
                isHTTPOnly: true, sameSite: "Lax")
        }
        let added = await engine.addCookies(
            [cookie(".nera-test.example", "kept"), cookie("www.nera-test.example", "sub"), cookie(".other.example", "other")], in: scope)
        let read = await engine.cookies(forSite: "nera-test.example", in: scope)
        await engine.removeWebsiteData(for: scope)
        let names = Set(read.map(\.name))
        guard added == 3, names == ["kept", "sub"], read.allSatisfy({ $0.isHTTPOnly && $0.isSecure && $0.sameSite == "Lax" }) else {
            return "cookies by site: added \(added), read \(names.sorted())"
        }
        return nil
    }

    /// Whether `MediaProbe` (EngineKit) flags a page whose video file is missing (404), once the video has failed. It must
    /// not: switching engines wouldn't help.
    @MainActor public static func flagsMissingVideo(_ page: any WebPage) async throws -> Bool {
        let failed = "(() => { const v = document.querySelector('video'); return !!v.error || v.networkState === 3; })()"
        let deadline = ContinuousClock.now + .seconds(8)
        while await page.evaluate(failed) != "true" {
            guard ContinuousClock.now < deadline else { throw ConformanceFailure("the missing video never failed") }
            try await Task.sleep(for: .milliseconds(100))
        }
        return await page.evaluate(MediaProbe.script) == MediaProbe.unsupported
    }

    /// A half-second, 16×16 black H.264 (baseline) MP4, as a `data:` URL.
    public static let h264Video =
        "data:video/mp4;base64,"
        + [
            "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAM2bW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAAfQAAQAAAQAA",
            "AAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAA",
            "AmF0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAfQAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAA",
            "AAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAH0AAAAAAABAAAAAAHZbWRpYQAAACBtZGhk",
            "AAAAAAAAAAAAAAAAAAAoAAAAFABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABhG1p",
            "bmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAURzdGJsAAAAuHN0c2QA",
            "AAAAAAAAAQAAAKhhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFUxhdmM2MS4xOS4xMDEgbGli",
            "eDI2NAAAAAAAAAAAAAAAGP//AAAALmF2Y0MBQsAK/+EAFmdCwArZHsBEAAADAAQAAAMAUDxImSABAAVoy4PLIAAAABBwYXNwAAAA",
            "AQAAAAEAAAAUYnRydAAAAAAAACqAAAAAAAAAABhzdHRzAAAAAAAAAAEAAAAFAAAEAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAHHN0",
            "c2MAAAAAAAAAAQAAAAEAAAAFAAAAAQAAAChzdHN6AAAAAAAAAAAAAAAFAAACgwAAAAkAAAAKAAAACQAAAAkAAAAUc3RjbwAAAAAA",
            "AAABAAADZgAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRv",
            "bwAAABxkYXRhAAAAAQAAAABMYXZmNjEuNy4xMDAAAAAIZnJlZQAAArBtZGF0AAACcQYF//9t3EXpvebZSLeWLNgg2SPu73gyNjQg",
            "LSBjb3JlIDE2NCByMzEwOCAzMWUxOWY5IC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyMyAtIGh0",
            "dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFs",
            "eXNlPTB4MToweDExMSBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2",
            "IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3Fw",
            "X29mZnNldD0tMiB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBp",
            "bnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlpbnQ9",
            "MjUwIGtleWludF9taW49MTAgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVl",
            "PTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAA",
            "AAAKZYiED/JigADD7gAAAAVBmjgf6gAAAAZBmlQH+oAAAAAFQZpgO9QAAAAFQZqAN9Q=",
        ].joined()
}
