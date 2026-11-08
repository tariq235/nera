// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import BrowserCore

@Suite("Open tab search")
struct OpenTabSearchTests {
    func tab(_ url: String, _ title: String) -> Tab { Tab(id: UUID(), url: URL(string: url), title: title, lastActiveAt: Date()) }

    @Test func typingASiteThatsOpenFindsItsTabFirstAndStrongly() {
        let github = tab("https://github.com/example/nera", "Nera · GitHub")
        let news = tab("https://news.ycombinator.com/", "Hacker News")
        let docs = tab("https://docs.github.com/en", "GitHub Docs")
        let tabs = [news, docs, github]
        for typed in ["github.com", "GitHub.com", "https://github.com/", "www.github.com"] {
            let best = OpenTabSearch.matches(typed, in: tabs).first
            #expect(best?.tab.id == github.id && best?.isStrong == true, "\(typed)")
        }
        let prefix = OpenTabSearch.matches("git", in: tabs)
        #expect(prefix.first?.isStrong == true && prefix.count == 2, "a prefix of the site is strong too")
        #expect(OpenTabSearch.matches("hacker", in: tabs).first?.tab.id == news.id, "a word of the title")
        #expect(OpenTabSearch.matches("ycombinator", in: tabs).first?.isStrong == true)
    }

    @Test func weakMatchesDontJumpAhead() {
        let tabs = [tab("https://example.com/report-2026", "Quarterly numbers")]
        let match = OpenTabSearch.matches("2026", in: tabs).first
        #expect(match != nil && match?.isStrong == false, "only in the address: listed, but opening or searching stays first")
        #expect(OpenTabSearch.matches("  ", in: tabs).isEmpty)
        #expect(OpenTabSearch.matches("zzz", in: tabs).isEmpty)
    }

    @Test func eachTabOnceAndAtMostTheLimit() {
        let one = tab("https://a.example", "A")
        let many = (0..<20).map { tab("https://site\($0).example", "Site \($0)") }
        #expect(OpenTabSearch.matches("site", in: many).count == 8)
        #expect(OpenTabSearch.matches("a.example", in: [one, one]).count == 1)
    }
}
