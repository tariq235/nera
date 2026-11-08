// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import SecurityPolicy
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// Video and DRM: streaming sites and sites the user chose open with WebKit; tabs move between engines
/// before any request, signed in.
@MainActor
@Suite("Site engines")
struct SiteEngineTests {
    let chromium = FakeEngine(id: "chromium")
    let webKit = FakeEngine(id: "webkit")

    func model() -> AppModel {
        let m = AppModel(
            store: .load(persistence: InMemoryStore()), registry: EngineRegistry([chromium, webKit]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))
        return m
    }

    func page(_ m: AppModel, engine: String, timeout: Int = 50) async throws -> FakePage {
        for _ in 0..<timeout where (m.selectedPage as? FakePage)?.engineID != engine { try await Task.sleep(for: .milliseconds(20)) }
        return try #require(m.selectedPage as? FakePage)
    }

    func cookie(_ domain: String, _ name: String) -> WebCookie {
        WebCookie(domain: domain, name: name, value: "secret", path: "/", expires: nil, isSecure: true, isHTTPOnly: true, sameSite: nil)
    }

    @Test func streamingSitesAndChosenSitesUseWebKit() throws {
        var profile = Profile(id: UUID(), name: "P")
        #expect(SiteEngines.preferred(for: URL(string: "https://www.netflix.com/browse"), in: profile) == .webKit)
        #expect(SiteEngines.preferred(for: URL(string: "https://open.spotify.com/album/1"), in: profile) == .webKit)
        #expect(SiteEngines.preferred(for: URL(string: "https://spotify.com/"), in: profile) == nil, "only the web player")
        #expect(SiteEngines.preferred(for: URL(string: "https://example.com"), in: profile) == nil)
        #expect(SiteEngines.preferred(for: URL(string: "https://x.com/home"), in: profile) == .webKit, "X's video is H.264 only")
        #expect(SiteEngines.preferred(for: URL(string: "https://mobile.twitter.com/"), in: profile) == .webKit)
        profile.siteEngines = ["x.com": .chromium]
        #expect(SiteEngines.preferred(for: URL(string: "https://x.com/home"), in: profile) == .chromium, "the user can keep X on Chromium")
        profile.siteEngines = ["x.com": .webKit, "netflix.com": .chromium]
        #expect(SiteEngines.preferred(for: URL(string: "https://video.x.com/a"), in: profile) == .webKit, "subdomains follow")
        #expect(SiteEngines.preferred(for: URL(string: "https://www.netflix.com/"), in: profile) == .chromium, "the user's choice wins")
        #expect(SiteEngines.preferred(for: URL(string: "file:///tmp/a.html"), in: profile) == nil)
        #expect(SiteEngines.cookieSite(of: URL(string: "https://open.spotify.com/x")!) == "spotify.com")
        #expect(SiteEngines.cookieSite(of: URL(string: "https://www.bbc.co.uk/iplayer")!) == "bbc.co.uk")
        #expect(SiteEngines.cookieSite(of: URL(string: "https://127.0.0.1/")!) == nil)
    }

    @Test func aLinkToAStreamingSiteIsStoppedAndTheTabMovesSignedIn() async throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://accounts.spotify.com/login")!, .newTab)))
        let tab = try #require(m.state.selectedTab)
        let first = try #require(m.selectedPage as? FakePage)
        #expect(first.engineID == "chromium")
        let profileID = try #require(m.state.currentProfile?.id)
        chromium.storedCookies[profileID] = [cookie(".spotify.com", "sp_dc"), cookie(".google.com", "SID")]

        // The page's policy hands the redirect to the other engine before any request.
        let route = try #require(chromium.configurations.last?.policy.engineRoute)
        let player = URL(string: "https://open.spotify.com/")!
        #expect(route.wantsOtherEngine(player) && !route.wantsOtherEngine(URL(string: "https://spotify.com/")!))
        first.simulate(.navigationBlocked(player, .otherEngine))

        let moved = try await page(m, engine: "webkit")
        #expect(moved.id == tab.id && first.isClosed && moved.loads == [player])
        #expect(webKit.addedCookies[profileID]?.map(\.name) == ["sp_dc"], "only the site's cookies go along")
        #expect(m.pages.lastBlocked == nil, "never shown as a blocked navigation")
    }

    @Test func typingAStreamingAddressIntoATabMovesIt() async throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://example.com/")!, .newTab)))
        let first = try #require(m.selectedPage as? FakePage)
        m.send(.tab(.open(URL(string: "https://www.netflix.com/")!, .currentTab)))
        let moved = try await page(m, engine: "webkit")
        #expect(first.isClosed && first.loads.count == 1, "Chromium never loaded it")
        #expect(moved.loads.last?.host() == "www.netflix.com")
    }

    @Test func popupsKeepTheirOpenerAndEngine() {
        var policy = NavigationPolicy()
        policy.engineRoute = EngineRoute { _ in true }
        let url = URL(string: "https://accounts.google.com/o/oauth2")!
        #expect(policy.decide(url, trigger: .linkClick) == .block(.otherEngine))
        #expect(policy.decide(url, trigger: .userTyped) == .allow, "typed loads were routed by Nera already")
        #expect(policy.decide(url, trigger: .redirect, isMainFrame: false) == .allow, "frames stay")
        #expect(policy.forChildPage.decide(url, trigger: .linkClick) == .allow, "popups never move")
    }

    @Test func choosingAnEngineForASiteReopensItsTabs() async throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://videos.example/watch")!, .newTab)))
        let page = try #require(m.selectedPage as? FakePage)
        m.mediaSuggestions[page.id] = "videos.example"
        #expect(m.mediaSuggestion == "videos.example")
        m.setEngine(.webKit, forSite: "videos.example")
        #expect(m.state.currentProfile?.siteEngines?["videos.example"] == .webKit)
        #expect(m.mediaSuggestion == nil)
        let moved = try await self.page(m, engine: "webkit")
        #expect(page.isClosed)
        // Back to Chromium: that's the default, so the choice is cleared rather than stored.
        m.setEngine(.chromium, forSite: "videos.example")
        #expect(m.state.currentProfile?.siteEngines == nil || m.state.currentProfile?.siteEngines?.isEmpty == true)
        _ = try await self.page(m, engine: "chromium")
        #expect(moved.isClosed)
        // A built-in WebKit site needs an explicit Chromium choice.
        m.setEngine(.chromium, forSite: "netflix.com")
        #expect(m.state.currentProfile?.siteEngines?["netflix.com"] == .chromium)
    }

    @Test func movingABackgroundTabKeepsTheSelectedOne() async throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://videos.example/a")!, .newTab)))
        let background = try #require(m.state.selectedTab)
        _ = m.selectedPage  // pages are made when shown
        m.send(.tab(.open(URL(string: "https://example.com/")!, .newTab)))
        let selected = try #require(m.state.selectedTab)
        _ = m.selectedPage
        #expect(m.pages.engineID(of: background.id) == "chromium")
        m.setEngine(.webKit, forSite: "videos.example")
        for _ in 0..<50 where m.pages.engineID(of: background.id) != "webkit" { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.pages.engineID(of: background.id) == "webkit")
        #expect(m.pages.activeTabID == selected.id)
    }

    @Test func theSuggestionGoesAwayOffItsSite() throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://videos.example/watch")!, .newTab)))
        let page = try #require(m.selectedPage as? FakePage)
        m.mediaSuggestions[page.id] = "videos.example"
        #expect(m.mediaSuggestion == "videos.example")
        page.simulateState { $0.url = URL(string: "https://news.example/") }
        #expect(m.mediaSuggestion == nil)
    }

    @Test func notNowHidesTheSuggestionForTheSession() throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://videos.example/watch")!, .newTab)))
        let page = try #require(m.selectedPage as? FakePage)
        m.mediaSuggestions[page.id] = "videos.example"
        m.dismissMediaSuggestion()
        #expect(m.mediaSuggestion == nil)
    }

    @Test func theMediaProbeFlagsUnplayableVideoUnlessTheUserChoseChromium() async throws {
        let m = model()
        m.send(.tab(.open(URL(string: "https://videos.example/watch")!, .newTab)))
        let page = try #require(m.selectedPage as? FakePage)
        page.evaluateResult = { $0 == MediaProbe.script ? MediaProbe.unsupported : nil }
        page.simulate(.navigationFinished(URL(string: "https://videos.example/watch")))
        for _ in 0..<80 where m.mediaSuggestion == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(m.mediaSuggestion == "videos.example")

        let profileID = try #require(m.state.currentProfile?.id)
        m.send(.library(.setSiteEngine(profileID: profileID, site: "videos.example", .chromium)))
        page.simulate(.navigationFinished(URL(string: "https://videos.example/watch")))
        #expect(m.mediaSuggestion == nil, "a site the user keeps on Chromium isn't flagged again")
        try await Task.sleep(for: .seconds(3.5))
        #expect(m.mediaSuggestion == nil)
    }
}
