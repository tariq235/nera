// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import BrowserCore

@Suite("Omnibox")
struct OmniboxTests {
    let engine = SearchEngine.duckDuckGo

    @Test(arguments: [
        ("swift.org", "https://swift.org"),
        ("github.com/apple/swift", "https://github.com/apple/swift"),
        ("https://example.com/a?b=c", "https://example.com/a?b=c"),
        ("http://neverssl.com", "http://neverssl.com"),
        ("localhost:3000", "http://localhost:3000"),
        ("localhost", "http://localhost"),
        ("127.0.0.1:8080/x", "http://127.0.0.1:8080/x"),
        ("192.168.1.1", "https://192.168.1.1"),
        ("about:blank", "about:blank"),
        ("xn--bcher-kva.example", "https://xn--bcher-kva.example"),
        ("  apple.com  ", "https://apple.com"),
    ])
    func urls(input: String, expected: String) {
        #expect(Omnibox.parse(input, engine: engine) == .url(URL(string: expected)!))
    }

    @Test(arguments: ["what is swift", "swift", "2+2", "foo.", "how to use git.rebase now", "a..b"])
    func searches(input: String) {
        guard case .search(let q, let url)? = Omnibox.parse(input, engine: engine) else {
            Issue.record("expected search for \(input)")
            return
        }
        #expect(q == input)
        #expect(url.host() == "duckduckgo.com")
    }

    @Test func searchQueryIsEncoded() {
        let r = Omnibox.parse("c++ & rust", engine: engine)
        #expect(r?.url.absoluteString == "https://duckduckgo.com/?q=c%2B%2B%20%26%20rust")
    }

    @Test func emptyInputIsIgnored() {
        #expect(Omnibox.parse("   ", engine: engine) == nil)
    }

    @Test func javascriptIsPassedThroughForPolicyToBlock() {
        // Omnibox only classifies; SecurityKit.NavigationPolicy blocks it (tested there).
        #expect(Omnibox.parse("javascript:alert(1)", engine: engine) == .url(URL(string: "javascript:alert(1)")!))
    }
}
