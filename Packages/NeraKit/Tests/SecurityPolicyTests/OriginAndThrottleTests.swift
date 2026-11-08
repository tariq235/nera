// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import SecurityPolicy

@Suite("SecurityOrigin")
struct SecurityOriginTests {
    @Test func webOriginsDropDefaultPortsAndLowercase() {
        #expect(SecurityOrigin(url: URL(string: "HTTPS://Example.COM:443/path?q")).description == "https://example.com")
        #expect(SecurityOrigin(url: URL(string: "http://localhost:3000/")).description == "http://localhost:3000")
        #expect(SecurityOrigin(url: URL(string: "http://example.com:80")).port == nil)
    }

    @Test func dataAndMissingURLsAreOpaque() {
        #expect(SecurityOrigin(url: URL(string: "data:text/html,hi")).isOpaque)
        #expect(SecurityOrigin(url: nil).isOpaque)
        #expect(SecurityOrigin.opaque.description == "This page")
    }

    @Test func secureMeansHTTPSOrLoopback() {
        #expect(SecurityOrigin(url: URL(string: "https://a.example")).isSecure)
        #expect(SecurityOrigin(url: URL(string: "http://127.0.0.1:8080")).isSecure)
        #expect(!SecurityOrigin(url: URL(string: "http://a.example")).isSecure)
    }

    @Test func lookAlikeHostsStayDistinct() {
        // Punycode hosts are compared and shown as-is, never "prettified" into a look-alike.
        let real = SecurityOrigin(url: URL(string: "https://apple.com"))
        let fake = SecurityOrigin(url: URL(string: "https://xn--pple-43d.com"))
        #expect(real != fake)
        #expect(fake.description == "https://xn--pple-43d.com")
    }
}

@Suite("DialogThrottle")
struct DialogThrottleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func allowsUpToTheLimitThenSuppressesUntilReset() {
        var throttle = DialogThrottle(limit: 3, window: 5)
        var shown = [0.0, 1, 2, 3, 60].map { throttle.shouldShow(at: t0 + $0) }
        #expect(shown == [true, true, true, false, false])  // stays suppressed even after the window
        #expect(throttle.isSuppressed)
        throttle.reset()
        shown = [throttle.shouldShow(at: t0 + 61)]
        #expect(shown == [true])
    }

    @Test func slowDialogsAreNeverSuppressed() {
        var throttle = DialogThrottle(limit: 3, window: 5)
        let shown = (0..<20).map { throttle.shouldShow(at: t0 + Double($0) * 6) }
        #expect(shown.allSatisfy { $0 })
    }
}
