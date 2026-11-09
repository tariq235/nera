// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// ⌘N: browser windows share the library, each with its own Space and tab (ADR-0013).
@MainActor
struct MultiWindowTests {
    func main() -> AppModel {
        AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
    }

    @Test func windowsShareTheLibraryButEachKeepsItsTab() throws {
        let first = main()
        first.send(.tab(.open(URL(string: "https://a.example")!, .newTab)))
        let a = try #require(first.state.selectedTabID)
        let second = AppModel.window(sharing: first)
        #expect(second.state.selectedTabID == nil, "a new window opens without a tab")
        #expect(second.state.selectedSpaceID == first.state.selectedSpaceID, "on the same Space")
        second.send(.tab(.open(URL(string: "https://b.example")!, .newTab)))
        let b = try #require(second.state.selectedTabID)
        #expect(b != a)
        #expect(first.state.selectedTabID == a, "the first window keeps its tab")
        #expect(first.state.locate(b) != nil, "and sees the new tab in the shared sidebar")
        first.send(.tab(.close(a)))
        #expect(second.state.selectedTabID == b, "closing a tab in one window leaves the other's alone")
        #expect(second.state.locate(a) == nil)
    }

    @Test func aTabClosedInAnotherWindowIsNoLongerShown() throws {
        let first = main()
        first.send(.tab(.open(URL(string: "https://a.example")!, .newTab)))
        let a = try #require(first.state.selectedTabID)
        let second = AppModel.window(sharing: first)
        second.send(.tab(.select(a)))
        #expect(second.state.selectedTabID == a)
        first.send(.tab(.close(a)))
        #expect(second.state.selectedTab == nil, "the other window shows no tab instead of a closed one")
        second.send(.tab(.open(URL(string: "https://c.example")!, .newTab)))  // and it can carry on
        #expect(second.state.selectedTab?.url?.host() == "c.example")
    }

    @Test func pagesShownInAnyWindowSurviveMemoryPressure() throws {
        let first = main()
        first.send(.tab(.open(URL(string: "https://a.example")!, .newTab)))
        let second = AppModel.window(sharing: first)
        second.send(.tab(.open(URL(string: "https://b.example")!, .newTab)))
        let a = try #require(first.selectedPage?.id)
        let b = try #require(second.selectedPage?.id)
        first.pages.handleMemoryPressure(.critical)
        #expect(first.pages.existingPage(for: a) != nil && first.pages.existingPage(for: b) != nil)
        second.windowClosed()
        _ = first.selectedPage  // the remaining window draws its page
        first.pages.handleMemoryPressure(.critical)
        #expect(first.pages.existingPage(for: b) == nil, "once its window closes, its page can be freed")
        #expect(first.pages.existingPage(for: a) != nil)
    }

    @Test func safeBrowsingWarningsAreSharedByAllWindows() {
        let first = main()
        let second = AppModel.window(sharing: first)
        #expect(first.safetyBox === second.safetyBox)
    }
}
