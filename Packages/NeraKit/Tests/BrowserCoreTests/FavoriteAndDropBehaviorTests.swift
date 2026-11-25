// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// Favorites keep their site, closing one sends it home, and a tab dropped on the page joins it in Split View, as in
/// Arc.
@Suite("Favorite and drop behavior")
struct FavoriteAndDropBehaviorTests {
    let env = TestEnv()

    func open(_ s: inout BrowserState, _ url: String, _ d: TabAction.Disposition = .newTab) -> UUID {
        _ = Reducer.reduce(&s, .tab(.open(URL(string: url)!, d)), env.reducer)
        return s.selectedTabID!
    }

    func favorite(_ s: inout BrowserState, _ url: String) -> UUID {
        let id = open(&s, url)
        _ = Reducer.reduce(&s, .tab(.addToFavorites(id)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.select(id)), env.reducer)
        return id
    }

    @Test func anotherSiteTypedOnAFavoriteOpensANewTab() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let x = favorite(&s, "https://x.com")
        let opened = open(&s, "https://adblock.example/test", .currentTab)
        #expect(opened != x, "a new tab, not the Favorite")
        #expect(s.tab(withID: x)?.url == URL(string: "https://x.com"), "the Favorite keeps its page")
        #expect(s.spaces[0].today.first?.tabs.first?.id == opened)
    }

    @Test func theSameSiteTypedOnAFavoriteStaysInIt() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let x = favorite(&s, "https://x.com")
        let opened = open(&s, "https://www.x.com/notifications", .currentTab)
        #expect(opened == x && s.tab(withID: x)?.url == URL(string: "https://www.x.com/notifications"))
    }

    @Test func closingAFavoriteSendsItBackToItsOwnPage() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let x = favorite(&s, "https://x.com")
        _ = open(&s, "https://x.com/someone/status/1", .currentTab)
        let effects = Reducer.reduce(&s, .tab(.close(x)), env.reducer)
        #expect(s.tab(withID: x)?.url == URL(string: "https://x.com"))
        #expect(effects.contains(.discardPage(tabID: x)))
        #expect(s.profiles[0].favorites.contains { $0.id == x }, "it stays a Favorite")
    }

    @Test func aTabDroppedOnThePageJoinsItInSplitViewOnThatSide() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let b = open(&s, "https://b.example")
        _ = Reducer.reduce(&s, .tab(.dropIntoSplit(a, beside: b, leading: true)), env.reducer)
        #expect(s.selectedSplit?.tabs.map(\.id) == [a, b] && s.selectedTabID == a)
        let c = open(&s, "https://c.example")
        let d = open(&s, "https://d.example")
        _ = Reducer.reduce(&s, .tab(.dropIntoSplit(c, beside: d, leading: false)), env.reducer)
        #expect(s.selectedSplit?.tabs.map(\.id) == [d, c])
    }

    @Test func aTabDroppedOnAFavoritesPageSplitsWithACopy() throws {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let t = open(&s, "https://t.example")
        let x = favorite(&s, "https://x.com")
        _ = Reducer.reduce(&s, .tab(.dropIntoSplit(t, beside: x, leading: true)), env.reducer)
        let split = try #require(s.selectedSplit)
        #expect(split.tabs.first?.id == t && split.tabs.last?.url == URL(string: "https://x.com"))
        #expect(s.profiles[0].favorites.contains { $0.id == x }, "the Favorite stays put")
    }

    @Test func droppingATabOnItselfOrItsOwnSplitChangesNothing() {
        var s = BrowserState.initial(uuid: env.nextUUID)
        let a = open(&s, "https://a.example")
        let b = open(&s, "https://b.example", .splitWithCurrent)
        let before = s
        _ = Reducer.reduce(&s, .tab(.dropIntoSplit(a, beside: a, leading: true)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.dropIntoSplit(a, beside: b, leading: true)), env.reducer)
        #expect(s == before)
    }
}
