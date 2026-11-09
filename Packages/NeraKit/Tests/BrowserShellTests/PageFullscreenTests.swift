// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import Testing

@testable import BrowserShell

/// A video's full screen: Chromium fills Nera's window with the page; WebKit uses a window of its own. Either way the
/// sidebar can slide in with Exit Full Screen, and choosing another tab ends it.
@MainActor
@Suite("Page full screen")
struct PageFullscreenTests {
    let engine = FakeEngine()

    func model() -> AppModel {
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([engine]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))
        return m
    }

    func open(_ m: AppModel, _ url: String) throws -> (BrowserCore.Tab, FakePage) {
        m.send(.tab(.open(URL(string: url)!, .newTab)))
        let tab = try #require(m.state.selectedTab)
        let profile = try #require(m.state.currentProfile)
        let page = try #require(m.pages.page(for: tab, profile: profile) as? FakePage)
        return (tab, page)
    }

    @Test func chromiumFullScreenFillsTheWindow() throws {
        let m = model()
        let (_, page) = try open(m, "https://video.example")
        page.simulate(.fullscreenChanged(true))
        #expect(m.isPageFullscreen && m.isPageFullscreenInWindow)
        m.exitPageFullscreen()
        #expect(page.exitFullscreenCount == 1, "the sidebar's Exit Full Screen asks the page to leave")
        page.simulate(.fullscreenChanged(false))
        #expect(!m.isPageFullscreen && !m.isPageFullscreenInWindow)
    }

    @Test func webKitFullScreenKeepsTheWindowAsItIs() throws {
        let m = model()
        let (_, page) = try open(m, "https://x.example")
        page.showsFullscreenInOwnWindow = true
        page.simulate(.fullscreenChanged(true))
        #expect(m.isPageFullscreen, "the sidebar offers Exit Full Screen")
        #expect(!m.isPageFullscreenInWindow, "WebKit's own window shows it: Nera's window stays as it is")
        m.exitPageFullscreen()
        #expect(page.exitFullscreenCount == 1)
    }

    @Test func choosingAnotherTabEndsTheVideosFullScreen() throws {
        let m = model()
        let (a, pa) = try open(m, "https://video.example")
        let (_, pb) = try open(m, "https://other.example")
        m.send(.tab(.select(a.id)))
        pa.simulate(.fullscreenChanged(true))
        m.exitFullscreenOfUnselectedPage()
        #expect(pa.exitFullscreenCount == 0, "still the selected tab")
        m.send(.tab(.select(pb.id)))
        m.exitFullscreenOfUnselectedPage()
        #expect(pa.exitFullscreenCount == 1)
    }
}
