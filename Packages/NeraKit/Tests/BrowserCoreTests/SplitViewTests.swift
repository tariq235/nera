// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// Split View.
@Suite("Split View")
struct SplitViewTests {
    let env = TestEnv()

    func open(_ s: inout BrowserState, _ url: String, _ d: TabAction.Disposition = .newTab) -> UUID {
        _ = Reducer.reduce(&s, .tab(.open(URL(string: url)!, d)), env.reducer)
        return s.selectedTabID!
    }

    @Test func openingInSplitViewPairsTheNewTabWithTheCurrentOne() throws {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let b = open(&s, "https://b.example", .splitWithCurrent)
        let split = try #require(s.selectedSplit)
        #expect(split.tabs.map(\.id) == [a, b] && s.selectedTabID == b)
        let c = open(&s, "https://c.example", .splitWithCurrent)
        #expect(s.selectedSplit?.tabs.map(\.id) == [a, b, c], "inserted after the current tab")
        _ = open(&s, "https://d.example", .splitWithCurrent)
        #expect(s.selectedSplit?.tabs.count == 4)
        let e = open(&s, "https://e.example", .splitWithCurrent)
        #expect(s.selectedSplit == nil && s.selectedTabID == e, "a full split falls back to a normal tab")
    }

    @Test func existingTabsCanBeSplitSeparatedAndRotated() throws {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let b = open(&s, "https://b.example")
        _ = Reducer.reduce(&s, .tab(.splitWith(a, other: b)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.select(a)), env.reducer)
        #expect(s.selectedSplit?.tabs.map(\.id) == [a, b])
        #expect(s.spaces[0].today.count == 1, "one split node replaces the two tabs")
        _ = Reducer.reduce(&s, .tab(.setSplitAxis(b, .vertical)), env.reducer)
        #expect(s.selectedSplit?.axis == .vertical)
        _ = Reducer.reduce(&s, .tab(.removeFromSplit(b)), env.reducer)
        #expect(s.selectedSplit == nil && s.spaces[0].today.flatMap(\.tabs).map(\.id) == [a, b], "b goes right after a")
        _ = Reducer.reduce(&s, .tab(.splitWith(a, other: b)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.unsplit(a)), env.reducer)
        #expect(s.selectedSplit == nil && s.spaces[0].today.count == 2)
    }

    @Test func closingATabInASplitCollapsesIt() throws {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let b = open(&s, "https://b.example", .splitWithCurrent)
        _ = Reducer.reduce(&s, .tab(.close(b)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.select(a)), env.reducer)
        #expect(s.selectedSplit == nil && s.spaces[0].today.flatMap(\.tabs).map(\.id) == [a])
    }

    @Test func invalidSplitsAreIgnored() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let before = s
        _ = Reducer.reduce(&s, .tab(.splitWith(a, other: a)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.splitWith(a, other: UUID())), env.reducer)
        _ = Reducer.reduce(&s, .tab(.removeFromSplit(a)), env.reducer)
        #expect(s == before)
    }
}
