// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// Dragging Favorites and Spaces, and a tab's sound.
@Suite("Reducer: dragging and sound")
struct ReducerDragTests {
    /// Dragging Favorites: reorder them, drop a sidebar tab at a place among them, or drag one back into the sidebar.
    @Test func favoritesReorderAndMoveInAndOutByDragging() {
        var h = Harness()
        let a = h.open("https://a.example")
        let b = h.open("https://b.example")
        let c = h.open("https://c.example")
        h.send(.tab(.addToFavorites(a)))
        h.send(.tab(.addToFavorites(b)))
        h.send(.tab(.moveFavorite(b, before: a)))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [b, a])
        h.send(.tab(.moveFavorite(b, before: nil)))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [a, b], "nil: to the end")
        h.send(.tab(.moveFavorite(c, before: b)))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [a, c, b], "a sidebar tab becomes a Favorite there")
        #expect(h.state.selectedSpace?.today.contains { $0.id == c } == false)
        #expect(h.state.tab(withID: c)?.homeURL == URL(string: "https://c.example"))
        h.send(.tab(.moveFavorite(a, before: UUID())))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [a, c, b], "an unknown target changes nothing")
        h.send(.tab(.moveNode(c, to: .endOf(.pinned))))
        #expect(h.state.currentProfile?.favorites.map(\.id) == [a, b], "a Favorite dragged into the sidebar leaves the Favorites")
        #expect(h.state.selectedSpace?.pinned.last?.id == c)
    }

    @Test func spacesReorderByDragging() throws {
        var h = Harness()
        let first = h.state.selectedSpaceID
        h.send(.space(.create(title: "Work")))
        let work = h.state.selectedSpaceID
        h.send(.space(.create(title: "Study")))
        let study = h.state.selectedSpaceID
        let start = h.state.spaces.map(\.id)
        #expect(start.suffix(3) == [first, work, study])
        h.send(.space(.move(study, before: first)))
        #expect(h.state.spaces.map(\.id).suffix(3) == [study, first, work])
        h.send(.space(.move(study, before: nil)))
        #expect(h.state.spaces.map(\.id).suffix(3) == [first, work, study])
        h.send(.space(.move(study, before: study)))
        h.send(.space(.move(UUID(), before: first)))
        #expect(h.state.spaces.map(\.id).suffix(3) == [first, work, study], "invalid moves change nothing")
        #expect(h.state.selectedSpaceID == study, "moving doesn't switch Spaces")
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
}
