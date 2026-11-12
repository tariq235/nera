// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

struct Harness {
    let env = TestEnv()
    var state: BrowserState

    init() {
        let e = env
        state = .initial(uuid: { e.nextUUID() })
    }

    @discardableResult
    mutating func send(_ action: Action) -> [Effect] { Reducer.reduce(&state, action, env.reducer) }

    var space: Space { state.selectedSpace! }

    mutating func open(_ s: String) -> UUID {
        send(.tab(.open(URL(string: s)!, .newTab)))
        return state.selectedTabID!
    }
}

@Suite("Reducer")
struct ReducerTests {
    @Test func newTabGoesToTopOfTodayAndIsSelected() {
        var h = Harness()
        let a = h.open("https://a.example")
        let effects = h.send(.tab(.open(URL(string: "https://b.example")!, .newTab)))
        let b = h.state.selectedTabID!
        #expect(h.space.today.map(\.id) == [b, a])
        #expect(effects == [.load(tabID: b, url: URL(string: "https://b.example")!)])
    }

    @Test func currentTabDispositionNavigatesSelectedTab() {
        var h = Harness()
        let a = h.open("https://a.example")
        let effects = h.send(.tab(.open(URL(string: "https://c.example")!, .currentTab)))
        #expect(h.space.today.count == 1)
        #expect(h.state.tab(withID: a)?.url == URL(string: "https://c.example"))
        #expect(effects == [.load(tabID: a, url: URL(string: "https://c.example")!)])
    }

    @Test func closingTodayTabArchivesItAndSelectsNeighbor() {
        var h = Harness()
        let a = h.open("https://a.example")
        let b = h.open("https://b.example")  // order: b, a
        h.send(.tab(.select(a)))
        let effects = h.send(.tab(.close(a)))
        #expect(h.space.today.map(\.id) == [b])
        #expect(h.state.selectedTabID == b)
        #expect(h.state.archive.first?.tab.id == a)
        #expect(h.state.recentlyClosed.first?.tab.id == a)
        #expect(effects == [.discardPage(tabID: a)])
    }

    /// On GitHub, ⌘T a site, ⌘W: back on GitHub, not on the pinned tab above the new one (Arc does the same).
    @Test func closingATabGoesBackToTheTabUsedBeforeIt() {
        var h = Harness()
        let pinned = h.open("https://mail.example")
        h.send(.tab(.togglePin(pinned)))
        h.env.now += 60
        let github = h.open("https://github.com")
        h.env.now += 60
        let other = h.open("https://news.example")  // Today: other, github
        h.env.now += 60
        h.send(.tab(.select(github)))
        h.env.now += 60
        let facebook = h.open("https://facebook.com")  // Today: facebook, other, github; pinned above
        h.env.now += 5
        h.send(.tab(.close(facebook)))
        #expect(h.state.selectedTabID == github)
        _ = other
    }

    /// Change Icon…, and Edit Pinned Page › Use the Current Page.
    @Test func tabsTakeAnEmojiIconAndPinnedPagesCanMoveHome() throws {
        var h = Harness()
        let a = h.open("https://a.example/home")
        h.send(.tab(.setIcon(a, emoji: "  🚀✨ ")))
        #expect(h.state.tab(withID: a)?.customIcon == "🚀", "one emoji")
        h.send(.tab(.setIcon(a, emoji: nil)))
        #expect(h.state.tab(withID: a)?.customIcon == nil)
        h.send(.tab(.makeCurrentPageHome(a)))
        #expect(h.state.tab(withID: a)?.homeURL == nil, "Today tabs have no pinned page")
        h.send(.tab(.togglePin(a)))
        h.send(.tab(.didUpdate(a, url: URL(string: "https://a.example/inbox"), title: nil)))
        h.send(.tab(.makeCurrentPageHome(a)))
        #expect(h.state.tab(withID: a)?.homeURL == URL(string: "https://a.example/inbox"))
    }

    /// Mute stays with the tab (its page applies it whenever it's made again).
    @Test func tabsRememberBeingMuted() {
        var h = Harness()
        let a = h.open("https://a.example")
        #expect(h.state.tab(withID: a)?.isMuted == false)
        h.send(.tab(.setMuted(a, true)))
        #expect(h.state.tab(withID: a)?.isMuted == true)
        h.send(.tab(.setMuted(a, false)))
        #expect(h.state.tab(withID: a)?.isMuted == false)
    }

    /// Add Split View on a Favorite: its page and the new one side by side at the top of Today; the Favorite stays.
    @Test func aFavoriteCanStartASplitView() throws {
        var h = Harness()
        let fav = h.open("https://mail.example")
        h.send(.tab(.addToFavorites(fav)))
        h.send(.tab(.select(fav)))
        let effects = h.send(.tab(.open(URL(string: "https://docs.example")!, .splitWithCurrent)))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [fav])
        guard case .split(let split)? = h.space.today.first?.kind else {
            Issue.record("no split")
            return
        }
        #expect(split.tabs.map(\.url) == [URL(string: "https://mail.example"), URL(string: "https://docs.example")])
        #expect(h.state.selectedTabID == split.tabs[1].id)
        #expect(effects.count == 2)
    }

    /// ⌘Z after Clear brings Today back as it was (a split too); after closing a tab, that tab. Newest first.
    @Test func undoBringsBackTheTodayAClearRemovedOrTheLastClosedTab() throws {
        var h = Harness()
        let a = h.open("https://a.example")
        let b = h.open("https://b.example")
        h.send(.tab(.splitWith(b, other: a)))
        let c = h.open("https://c.example")
        let before = h.space.today
        h.env.now += 10
        h.send(.space(.clearToday))
        #expect(h.space.today.isEmpty && h.state.clearedToday != nil)
        h.env.now += 10
        let d = h.open("https://d.example")
        h.env.now += 10
        h.send(.tab(.close(d)))
        h.send(.tab(.undoClose))
        #expect(h.space.today.map(\.id) == [d], "the tab closed after the Clear comes back first")
        h.send(.tab(.undoClose))
        #expect(Array(h.space.today.prefix(before.count)) == before, "then Today as it was, split and all")
        #expect(h.state.selectedTabID == before.first?.tabs.first?.id)
        #expect(h.state.clearedToday == nil)
        #expect(!h.state.archive.contains { $0.tab.id == c }, "restored tabs leave the archive")
    }

    @Test func closingPinnedTabKeepsItButUnloads() {
        var h = Harness()
        let a = h.open("https://a.example")
        h.send(.tab(.togglePin(a)))
        let effects = h.send(.tab(.close(a)))
        #expect(h.space.pinned.map(\.id) == [a])
        #expect(h.state.archive.isEmpty)
        #expect(effects == [.discardPage(tabID: a)])
    }

    @Test func pinningRemembersHomeURLAndResetReturnsToIt() {
        var h = Harness()
        let a = h.open("https://a.example/home")
        h.send(.tab(.togglePin(a)))
        #expect(h.state.tab(withID: a)?.homeURL == URL(string: "https://a.example/home"))
        h.send(.tab(.didUpdate(a, url: URL(string: "https://a.example/deep/page"), title: "Deep")))
        let effects = h.send(.tab(.resetToHome(a)))
        #expect(h.state.tab(withID: a)?.url == URL(string: "https://a.example/home"))
        #expect(effects == [.load(tabID: a, url: URL(string: "https://a.example/home")!)])
        h.send(.tab(.togglePin(a)))
        #expect(h.space.pinned.isEmpty)
        #expect(h.state.tab(withID: a)?.homeURL == nil)
    }

    @Test func restoreLastClosedReopensAtTop() {
        var h = Harness()
        let a = h.open("https://a.example")
        _ = h.open("https://b.example")
        h.send(.tab(.close(a)))
        h.send(.tab(.restoreLastClosed))
        #expect(h.space.today.first?.id == a)
        #expect(h.state.selectedTabID == a)
        #expect(h.state.archive.contains { $0.id == a } == false)
        #expect(h.send(.tab(.restoreLastClosed)) == [])  // stack now empty
    }

    @Test func archiveSweepRemovesOnlyStaleUnselectedTodayTabs() {
        var h = Harness()
        let stale = h.open("https://stale.example")
        let pinned = h.open("https://pinned.example")
        h.send(.tab(.togglePin(pinned)))
        h.env.now += 13 * 3600
        let fresh = h.open("https://fresh.example")  // selected
        let effects = h.send(.library(.archiveSweep))
        #expect(h.space.today.map(\.id) == [fresh])
        #expect(h.space.pinned.map(\.id) == [pinned])
        #expect(h.state.archive.first?.tab.id == stale)
        #expect(effects == [.discardPage(tabID: stale)])
    }

    @Test func selectingSpaceRestoresMostRecentTab() {
        var h = Harness()
        let first = h.state.selectedSpaceID
        _ = h.open("https://old.example")
        h.env.now += 60
        let recent = h.open("https://recent.example")
        h.send(.space(.create(title: "Work")))
        #expect(h.state.selectedTabID == nil)
        h.send(.space(.select(first)))
        #expect(h.state.selectedTabID == recent)
    }

    @Test func adjacentSpaceWrapsAround() {
        var h = Harness()
        let first = h.state.selectedSpaceID
        h.send(.space(.create(title: "Two")))
        h.send(.space(.selectAdjacent(offset: 1)))
        #expect(h.state.selectedSpaceID == first)
        h.send(.space(.selectAdjacent(offset: -1)))
        #expect(h.state.selectedSpace?.title == "Two")
    }

    @Test func cannotDeleteLastSpace() {
        var h = Harness()
        h.send(.space(.delete(h.state.selectedSpaceID)))
        #expect(h.state.spaces.count == 1)
    }

    @Test func deletingSpaceDiscardsItsPages() {
        var h = Harness()
        h.send(.space(.create(title: "Temp")))
        let tab = h.open("https://x.example")
        let effects = h.send(.space(.delete(h.state.selectedSpaceID)))
        #expect(h.state.spaces.count == 1)
        #expect(effects == [.discardPage(tabID: tab)])
        #expect(h.state.tab(withID: tab) == nil)
    }

    @Test func favoritesMoveOutOfSpaceAndBack() {
        var h = Harness()
        let a = h.open("https://mail.example")
        h.send(.tab(.addToFavorites(a)))
        #expect(h.space.today.isEmpty)
        #expect(h.state.currentProfile?.favorites.map(\.id) == [a])
        h.send(.tab(.togglePin(a)))  // unfavorite
        #expect(h.state.currentProfile?.favorites.isEmpty == true)
        #expect(h.space.today.map(\.id) == [a])
    }

    @Test func folderToggleAndNestedTabRemoval() {
        var h = Harness()
        h.send(.space(.createFolder(title: "Docs")))
        let folderID = h.space.pinned[0].id
        h.send(.space(.toggleFolder(folderID)))
        guard case .folder(let f) = h.space.pinned[0].kind else {
            Issue.record("not a folder")
            return
        }
        #expect(f.isExpanded == false)

        var nodes = [
            Node(
                id: folderID,
                kind: .folder(
                    Folder(
                        title: "Docs",
                        children: [
                            .tab(Tab(id: UUID(), url: nil, lastActiveAt: .now))
                        ])))
        ]
        let inner = nodes[0].tabs[0].id
        #expect(nodes.removeTab(id: inner)?.id == inner)
        #expect(nodes[0].tabs.isEmpty)
    }

    @Test func splitWithOneTabLeftCollapses() {
        let t1 = Tab(id: UUID(), url: nil, lastActiveAt: .now)
        let t2 = Tab(id: UUID(), url: nil, lastActiveAt: .now)
        var nodes = [Node(id: UUID(), kind: .split(Split(tabs: [t1, t2])))]
        _ = nodes.removeTab(id: t1.id)
        #expect(nodes == [.tab(t2)])
    }

    @Test func tabCyclingWraps() {
        var h = Harness()
        let a = h.open("https://a.example")
        let b = h.open("https://b.example")  // order b, a
        h.send(.tab(.selectAdjacent(offset: 1)))
        #expect(h.state.selectedTabID == a)
        h.send(.tab(.selectAdjacent(offset: 1)))
        #expect(h.state.selectedTabID == b)
    }

    @Test func archiveIsCapped() {
        var h = Harness()
        for i in 0..<(BrowserState.archiveLimit + 5) {
            let id = h.open("https://\(i).example")
            h.send(.tab(.close(id)))
        }
        #expect(h.state.archive.count == BrowserState.archiveLimit)
        #expect(h.state.recentlyClosed.count == BrowserState.recentlyClosedLimit)
    }
}
