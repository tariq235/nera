// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import CommandBar

/// A11Y-005: VoiceOver hears the command bar's suggestions.
@Suite("Command bar speech")
struct SuggestionSpeechTests {
    let rows: [CommandBarView.Suggestion] = [
        .init(
            id: "search", title: "nera", subtitle: "Search DuckDuckGo", symbol: "magnifyingglass",
            kind: .search(URL(string: "https://duckduckgo.com/?q=nera")!)),
        .init(
            id: "t", title: "Nera Docs", subtitle: "Switch to Tab · docs.nera.dev", symbol: "arrow.right.square",
            kind: .switchTo(UUID())),
    ]

    @Test func eachRowReadsAsOneElement() {
        #expect(SuggestionSpeech.label(rows[1]) == "Nera Docs, Switch to Tab · docs.nera.dev")
    }

    @Test func movingTheHighlightAnnouncesTheRowAndItsPosition() {
        #expect(SuggestionSpeech.highlighted(rows, at: 1) == "Nera Docs, Switch to Tab · docs.nera.dev, 2 of 2")
        #expect(SuggestionSpeech.highlighted(rows, at: 2) == nil)
        #expect(SuggestionSpeech.highlighted([], at: 0) == nil)
    }

    @Test func aNewListIsAnnouncedWithWhatReturnOpens() {
        #expect(SuggestionSpeech.list(rows) == "2 suggestions. nera, Search DuckDuckGo")
        #expect(SuggestionSpeech.list(Array(rows.prefix(1))) == "1 suggestion. nera, Search DuckDuckGo")
        #expect(SuggestionSpeech.list([]) == nil)
    }
}
