// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Foundation
import Testing

struct SiteCompletionTests {
    let history = ["https://www.youtube.com/watch?v=1", "https://youronlinechoices.com", "https://github.com/x"].compactMap(
        URL.init(string:))

    @Test func completesTheFirstSiteThatStartsWithTheText() {
        #expect(SiteCompletion.complete("you", candidates: history) == "youtube.com", "most relevant first, without www.")
        #expect(SiteCompletion.complete("YOUR", candidates: history) == "youronlinechoices.com")
        #expect(SiteCompletion.complete("git", candidates: history) == "github.com")
    }

    @Test func doesNotCompleteSearchesOrFinishedAddresses() {
        #expect(SiteCompletion.complete("", candidates: history) == nil)
        #expect(SiteCompletion.complete("you tube", candidates: history) == nil, "a search")
        #expect(SiteCompletion.complete("github.com", candidates: history) == nil, "already complete")
        #expect(SiteCompletion.complete("github.com/x", candidates: history) == nil, "a path is typed out")
        #expect(SiteCompletion.complete("zzz", candidates: history) == nil)
    }
}
