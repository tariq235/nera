// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import BrowserCore

/// The tab menu's Duplicate and Move to Space.
struct TabMenuActionTests {
    @Test func duplicateOpensTheSamePageRightBelowAndSelectsIt() throws {
        var h = Harness()
        let b = h.open("https://b.example")
        let a = h.open("https://a.example")  // Today: a, b
        let effects = h.send(.tab(.duplicate(a)))
        let copy = try #require(h.state.selectedTabID)
        #expect(copy != a)
        #expect(h.space.today.map(\.id) == [a, copy, b], "right below the original")
        #expect(h.state.tab(withID: copy)?.url == URL(string: "https://a.example"))
        #expect(effects == [.load(tabID: copy, url: URL(string: "https://a.example")!)])
    }

    @Test func moveToSpaceTakesTheTabToTheTopOfThatSpacesToday() throws {
        var h = Harness()
        let home = h.state.selectedSpaceID
        let keep = h.open("https://keep.example")
        let move = h.open("https://move.example")
        _ = h.send(.space(.create(title: "Work")))
        let work = try #require(h.state.spaces.first { $0.title == "Work" }?.id)
        _ = h.send(.space(.select(home)))
        _ = h.send(.tab(.select(keep)))
        _ = h.send(.tab(.moveToSpace(move, spaceID: work)))
        #expect(h.state.spaces.first { $0.id == work }?.today.first?.id == move)
        #expect(h.state.spaces.first { $0.id == home }?.today.map(\.id) == [keep])
        #expect(h.state.selectedSpaceID == home, "moving another tab doesn't switch Space")
        _ = h.send(.tab(.select(keep)))
        _ = h.send(.tab(.moveToSpace(keep, spaceID: work)))
        #expect(h.state.selectedSpaceID == work && h.state.selectedTabID == keep, "the selected tab is followed")
        #expect(h.send(.tab(.moveToSpace(keep, spaceID: work))).isEmpty, "to its own Space: nothing happens")
        #expect(h.state.spaces.first { $0.id == work }?.today.filter { $0.id == keep }.count == 1)
    }
}

struct TabRenameTests {
    @Test func aRenamedTabKeepsItsNameWhileThePageTitleChanges() throws {
        var h = Harness()
        let a = h.open("https://a.example")
        _ = h.send(.tab(.rename(a, title: "  Taxes  ")))
        #expect(h.state.tab(withID: a)?.displayTitle == "Taxes")
        _ = h.send(.tab(.didUpdate(a, url: nil, title: "Some page")))
        #expect(h.state.tab(withID: a)?.displayTitle == "Taxes", "the page title doesn't replace the name")
        _ = h.send(.tab(.rename(a, title: " ")))
        #expect(h.state.tab(withID: a)?.displayTitle == "Some page", "an empty name goes back to the page title")
    }

    @Test func tabsFromBeforeRenamingDecode() throws {
        let tab = Tab(id: UUID(), url: URL(string: "https://a.example"), title: "A", lastActiveAt: Date(timeIntervalSince1970: 0))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any])
        json["customTitle"] = nil
        let old = try JSONDecoder().decode(Tab.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.customTitle == nil && old.displayTitle == "A")
    }
}
