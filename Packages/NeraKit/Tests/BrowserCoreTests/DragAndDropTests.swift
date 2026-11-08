// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// drag and drop in the sidebar.
@Suite("Sidebar drag and drop")
struct DragAndDropTests {
    let env = TestEnv()

    struct Setup {
        var state: BrowserState
        let a: UUID, b: UUID, c: UUID
    }

    func setup() -> Setup {
        var s = BrowserState.initial(uuid: env.nextUUID)
        var ids: [UUID] = []
        for host in ["c", "b", "a"] {  // Today is newest first: a, b, c
            _ = Reducer.reduce(&s, .tab(.open(URL(string: "https://\(host).example")!, .newTab)), env.reducer)
            ids.append(s.selectedTabID!)
        }
        return Setup(state: s, a: ids[2], b: ids[1], c: ids[0])
    }

    func today(_ s: BrowserState) -> [String] { s.spaces[0].today.flatMap(\.tabs).compactMap { $0.url?.host() } }
    func pinned(_ s: BrowserState) -> [String] { s.spaces[0].pinned.flatMap(\.tabs).compactMap { $0.url?.host() } }
    func move(_ s: inout BrowserState, _ id: UUID, _ d: NodeDestination) { _ = Reducer.reduce(&s, .tab(.moveNode(id, to: d)), env.reducer) }

    @Test func reorderWithinTodayAndPinByDropping() throws {
        let f = setup()
        var s = f.state
        let a = f.a
        let c = f.c
        #expect(today(s) == ["a.example", "b.example", "c.example"])
        move(&s, c, .before(a))
        #expect(today(s) == ["c.example", "a.example", "b.example"])
        move(&s, a, .endOf(.pinned))
        #expect(pinned(s) == ["a.example"] && today(s) == ["c.example", "b.example"])
        #expect(s.spaces[0].pinned.flatMap(\.tabs).first?.homeURL?.host() == "a.example", "pinning keeps a home URL")
        move(&s, a, .before(c))
        #expect(pinned(s).isEmpty && today(s) == ["a.example", "c.example", "b.example"], "dropping into Today unpins")
        #expect(s.spaces[0].today.flatMap(\.tabs).first?.homeURL == nil)
    }

    @Test func spaceOnTheKeyboardFindsTheSelectedTabsFolder() throws {
        let f = setup()
        var s = f.state
        _ = Reducer.reduce(&s, .space(.createFolder(title: "Work")), env.reducer)
        let folder = try #require(s.spaces[0].pinned.first?.id)
        move(&s, f.a, .intoFolder(folder))
        #expect(s.folderID(containing: f.a) == folder)
        #expect(s.folderID(containing: f.b) == nil, "a tab outside any folder")
        _ = Reducer.reduce(&s, .tab(.select(f.b)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.selectAdjacent(offset: -1)), env.reducer)
        #expect(s.selectedTabID != f.b, "↑ moves to the previous tab")
    }

    @Test func foldersAcceptTabsButNeverThemselves() throws {
        let f = setup()
        var s = f.state
        let a = f.a
        let b = f.b
        _ = Reducer.reduce(&s, .space(.createFolder(title: "Work")), env.reducer)
        let folder = try #require(s.spaces[0].pinned.first?.id)
        move(&s, a, .intoFolder(folder))
        move(&s, b, .intoFolder(folder))
        guard case .folder(let f)? = s.spaces[0].pinned.first?.kind else {
            Issue.record("no folder")
            return
        }
        #expect(f.children.flatMap(\.tabs).compactMap { $0.url?.host() } == ["a.example", "b.example"])
        let before = s
        move(&s, folder, .intoFolder(folder))
        move(&s, folder, .before(a))  // a is inside the folder
        #expect(s == before, "a folder can't go into itself")
        move(&s, b, .before(a))
        guard case .folder(let f2)? = s.spaces[0].pinned.first?.kind else {
            Issue.record("no folder")
            return
        }
        #expect(f2.children.flatMap(\.tabs).compactMap { $0.url?.host() } == ["b.example", "a.example"], "reorder inside a folder")
    }

    @Test func splitsMoveWholeAndTabsCanBeDraggedOut() throws {
        let f = setup()
        var s = f.state
        let a = f.a
        let b = f.b
        let c = f.c
        _ = Reducer.reduce(&s, .tab(.splitWith(a, other: b)), env.reducer)
        let splitNode = try #require(s.spaces[0].today.first { if case .split = $0.kind { true } else { false } }?.id)
        move(&s, splitNode, .endOf(.pinned))
        #expect(pinned(s) == ["a.example", "b.example"] && today(s) == ["c.example"])
        move(&s, b, .before(c))
        #expect(pinned(s) == ["a.example"] && today(s) == ["b.example", "c.example"], "one tab out of a split")
    }

    @Test func dropsOnFavoritesAndInvalidDrops() {
        let f = setup()
        var s = f.state
        let a = f.a
        move(&s, a, .favorites)
        #expect(s.profiles[0].favorites.compactMap { $0.url?.host() } == ["a.example"])
        let before = s
        move(&s, UUID(), .endOf(.today))
        move(&s, before.spaces[0].today.flatMap(\.tabs)[0].id, .before(UUID()))
        #expect(s == before, "unknown items or targets change nothing")
    }
}

extension DragAndDropTests {
    @Test func foldersCanBeRenamedAndDeletedKeepingTheirTabs() throws {
        let f = setup()
        var s = f.state
        let a = f.a
        _ = Reducer.reduce(&s, .space(.createFolder(title: "Work")), env.reducer)
        let folder = try #require(s.spaces[0].pinned.first?.id)
        move(&s, a, .intoFolder(folder))
        _ = Reducer.reduce(&s, .space(.renameFolder(folder, title: "  Projects ")), env.reducer)
        guard case .folder(let f)? = s.spaces[0].pinned.first?.kind else {
            Issue.record("no folder")
            return
        }
        #expect(f.title == "Projects")
        _ = Reducer.reduce(&s, .space(.deleteFolder(folder)), env.reducer)
        #expect(pinned(s) == ["a.example"], "the tab stays where the folder was")
        #expect(!s.spaces[0].pinned.contains { $0.isFolder })
    }
}
