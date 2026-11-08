// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// Peek, Little Windows, Link Rules, ⌘1–9, the mini player and site styles, end to end on the fake engine.
@MainActor
@Suite("Browsing features")
struct BrowsingFeaturesTests {
    let engine = FakeEngine()

    func model() -> AppModel {
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([engine]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))  // while the welcome shows, links open as tabs
        return m
    }

    /// Opens a tab and makes it pinned; returns it and its live page.
    func pinnedTab(_ m: AppModel, _ url: String) throws -> (BrowserCore.Tab, FakePage) {
        m.send(.tab(.open(URL(string: url)!, .newTab)))
        let tab = try #require(m.state.selectedTab)
        m.send(.tab(.togglePin(tab.id)))
        let profile = try #require(m.state.currentProfile)
        let page = try #require(m.pages.page(for: tab, profile: profile) as? FakePage)
        return (tab, page)
    }

    func openChild(from page: FakePage, _ m: AppModel, url: String, disposition: NewPageDisposition = .foregroundTab) -> FakePage {
        let child = FakePage(id: UUID(), delegate: m.pages)
        let decision = Decision<NewPageDecision>(fallback: .discard) { _ in }
        page.simulate(.newPage(NewPageRequest(page: child, url: URL(string: url), disposition: disposition, decision: decision)))
        return child
    }

    @Test func linksFromPinnedTabsOpenInPeekAndCanBecomeTabs() throws {
        let m = model()
        let (pinned, page) = try pinnedTab(m, "https://mail.example")
        let tabs = m.state.spaces[0].today.count
        let child = openChild(from: page, m, url: "https://docs.example/file")
        #expect(m.peek == PeekPage(id: child.id, openerID: pinned.id))
        #expect(m.state.spaces[0].today.count == tabs, "no tab yet")
        #expect(m.peekPage === child)
        child.simulateState {
            $0.url = URL(string: "https://docs.example/file")
            $0.title = "File"
        }
        m.openPeekAsTab()
        #expect(m.peek == nil && m.state.selectedTabID == child.id, "the same page became the selected tab")
        #expect(m.state.selectedTab?.title == "File")
        #expect(m.pages.existingPage(for: child.id) === child, "nothing reloads")
    }

    @Test func peekClosesWithoutATraceAndRespectsTheSetting() throws {
        let m = model()
        let (_, page) = try pinnedTab(m, "https://mail.example")
        let child = openChild(from: page, m, url: "https://docs.example")
        m.closePeek()
        #expect(m.peek == nil && child.isClosed && m.pages.existingPage(for: child.id) == nil)
        m.send(.library(.setPeekLinks(false)))
        let second = openChild(from: page, m, url: "https://docs.example")
        #expect(m.peek == nil && m.state.selectedTabID == second.id, "with Peek off, links open as tabs")
        let popup = openChild(from: page, m, url: "https://auth.example", disposition: .popup)
        #expect(m.state.selectedTabID == popup.id, "popups (sign-in windows) are never peeked")
    }

    @Test func linksFromTodayTabsStillOpenAsTabs() {
        let m = model()
        m.send(.tab(.open(URL(string: "https://news.example")!, .newTab)))
        let page = m.pages.page(for: m.state.selectedTab!, profile: m.state.currentProfile!) as! FakePage
        let child = openChild(from: page, m, url: "https://story.example")
        #expect(m.peek == nil && m.state.selectedTabID == child.id)
    }

    @Test func linksFromOtherAppsOpenInALittleWindowThatCanMoveIntoTheBrowser() throws {
        let m = model()
        let before = m.state.spaces[0].today.count
        m.openFromOutside(URL(string: "https://slack.example/link")!)
        let id = try #require(m.pendingLittleWindow)
        #expect(m.state.spaces[0].today.count == before, "not a tab yet")
        let page = try #require(m.littlePage(id) as? FakePage)
        #expect(page.loads.last?.absoluteString == "https://slack.example/link")
        page.simulateState {
            $0.url = URL(string: "https://slack.example/link")
            $0.title = "Thread"
        }
        m.moveLittleWindowToBrowser(id)
        #expect(m.state.selectedTabID == id && m.state.selectedTab?.title == "Thread")
        #expect(m.pages.existingPage(for: id) === page)
        m.closeLittleWindow(id)  // the window closing afterwards must not destroy the adopted page
        #expect(!page.isClosed)
    }

    @Test func closingALittleWindowDiscardsItsPage() throws {
        let m = model()
        m.openFromOutside(URL(string: "https://slack.example/link")!)
        let id = try #require(m.pendingLittleWindow)
        let page = try #require(m.littlePage(id) as? FakePage)
        m.closeLittleWindow(id)
        #expect(page.isClosed && m.littleTabs.isEmpty)
    }

    @Test func linkRulesSendMatchingLinksToTheirSpace() throws {
        let m = model()
        m.send(.space(.create(title: "Work")))
        let work = try #require(m.state.spaces.last)
        let home = m.state.spaces[0]
        m.send(.space(.select(home.id)))
        m.send(.library(.addLinkRoute(pattern: "https://www.Figma.com/", spaceID: work.id)))
        #expect(m.state.settings.linkRoutes.map(\.pattern) == ["figma.com"])
        m.openFromOutside(URL(string: "https://www.figma.com/file/abc")!)
        #expect(m.state.selectedSpaceID == work.id && m.state.selectedTab?.url?.host() == "www.figma.com")
        #expect(m.pendingLittleWindow == nil)
    }

    @Test func commandNumberJumpsToFavoritesThenPinnedTabs() throws {
        let m = model()
        let (first, _) = try pinnedTab(m, "https://one.example")
        let (second, _) = try pinnedTab(m, "https://two.example")
        #expect(m.shortcutTab(1)?.id == first.id && m.shortcutTab(2)?.id == second.id)
        #expect(m.shortcutTab(9)?.id == second.id, "⌘9 is the last one")
        #expect(m.shortcutTab(3) == nil)
        m.send(.tab(.clearSelection))
        m.selectShortcutTab(2)
        #expect(m.state.selectedTabID == second.id)
    }

    @Test func miniPlayerShowsABackgroundTabPlayingSound() async throws {
        let m = model()
        let (music, page) = try pinnedTab(m, "https://music.example")
        #expect(m.mediaTab == nil, "the visible tab doesn't need a mini player")
        page.simulateState { $0.isAudible = true }
        m.send(.tab(.open(URL(string: "https://news.example")!, .newTab)))
        #expect(m.mediaTab?.id == music.id)
        page.evaluateResult = { _ in "paused" }
        m.toggleMedia(music)
        try await Task.sleep(for: .milliseconds(50))
        page.simulateState { $0.isAudible = false }
        #expect(m.pausedMediaTabID == music.id && m.mediaTab?.id == music.id, "stays to be resumed")
        #expect(page.evaluatedScripts.last == MediaScript.toggle)
        m.dismissMedia()
        #expect(m.mediaTab == nil)
    }

    @Test func siteStylesRestyleEveryPageOfTheirSite() async throws {
        let m = model()
        let (_, page) = try pinnedTab(m, "https://news.example")
        page.simulateState { $0.url = URL(string: "https://www.news.example/today") }
        var siteStyle = SiteStyle()
        siteStyle.isDark = true
        m.saveSiteStyle(siteStyle, site: "news.example")
        try await Task.sleep(for: .milliseconds(50))
        #expect(m.siteStyle(for: page) == siteStyle)
        let script = try #require(page.evaluatedScripts.last)
        #expect(script.contains("nera-siteStyle") && script.contains("invert(1)"))
        m.saveSiteStyle(nil, site: "news.example")
        try await Task.sleep(for: .milliseconds(50))
        #expect(page.evaluatedScripts.last == SiteStyleScript.apply(""), "deleting removes the style sheet")
        page.simulate(.navigationFinished(URL(string: "https://www.news.example/other")))
        try await Task.sleep(for: .milliseconds(50))
        #expect(page.evaluatedScripts.count == 2, "pages without a SiteStyle aren't touched")
    }

    @Test func zapAddsWhatWasPickedToTheSiteStyle() async throws {
        let m = model()
        let (_, page) = try pinnedTab(m, "https://news.example")
        page.simulateState { $0.url = URL(string: "https://news.example/") }
        page.evaluateResult = { $0 == SiteStyleScript.zapFinish ? ##"["#cookie-banner","body > aside"]"## : "started" }
        m.startZap()
        #expect(m.isZapping)
        m.finishZap()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!m.isZapping && m.siteStyle(for: page)?.zapped == ["#cookie-banner", "body > aside"])
    }
}
