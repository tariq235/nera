// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

extension Reducer {
    static func reduceTab(_ state: inout BrowserState, _ action: TabAction, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .open(let url, let disposition): open(&state, url, disposition, env)
        case .moveNode(let id, let destination): moveNode(&state, id, to: destination, env)
        case .splitWith(let id, let other): splitWith(&state, id, other: other)
        case .removeFromSplit(let id): editSplits(&state) { $0.extractFromSplit(id) }
        case .unsplit(let id): editSplits(&state) { $0.updateSplit(containing: id) { _ in false } }
        case .setSplitAxis(let id, let axis):
            editSplits(&state) {
                $0.updateSplit(containing: id) { split in
                    split.axis = axis
                    return true
                }
            }
        case .openChild(let id, let url, let openerID, let select):
            openChild(&state, id: id, url: url, openerID: openerID, select: select, env)
        case .select(let id): select(&state, id, env)
        case .clearSelection: clearSelection(&state)
        case .selectAdjacent(let offset): selectAdjacent(&state, offset, env)
        case .close(let id): close(&state, id, env)
        case .togglePin(let id): togglePin(&state, id)
        case .resetToHome(let id): resetToHome(&state, id)
        case .restoreLastClosed: restoreLastClosed(&state, env)
        case .didUpdate(let id, let url, let title): didUpdate(&state, id, url: url, title: title)
        case .addToFavorites(let id): addToFavorites(&state, id)
        case .move(let id, let section, let index): move(&state, id, section: section, index: index)
        case .rename(let id, let title): rename(&state, id, title: title)
        case .duplicate(let id): duplicate(&state, id, env)
        case .moveToSpace(let id, let spaceID): moveToSpace(&state, id, spaceID: spaceID, env)
        }
    }

    private static func rename(_ state: inout BrowserState, _ id: UUID, title: String) -> [Effect] {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateTab(&state, id) { $0.customTitle = name.isEmpty ? nil : name }
        return []
    }

    private static func duplicate(_ state: inout BrowserState, _ id: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard let (source, location) = state.locate(id), let url = source.url else { return [] }
        var spaceID = state.selectedSpaceID
        if case .space(let sid, _) = location { spaceID = sid }
        guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
        let copy = Tab(id: env.uuid(), url: url, title: source.title, lastActiveAt: env.now())
        if let index = state.spaces[si].today.firstIndex(where: { $0.id == id }) {
            state.spaces[si].today.insert(.tab(copy), at: index + 1)  // right below a Today tab
        } else {
            state.spaces[si].today.insert(.tab(copy), at: 0)
        }
        state.selectedSpaceID = spaceID
        state.selectedTabID = copy.id
        return [.load(tabID: copy.id, url: url)]
    }

    private static func moveToSpace(_ state: inout BrowserState, _ id: UUID, spaceID: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
        if case .space(let current, _)? = state.locate(id)?.location, current == spaceID { return [] }
        guard var tab = removeTabAnywhere(&state, id) else { return [] }
        tab.lastActiveAt = env.now()
        state.spaces[si].today.insert(.tab(tab), at: 0)
        if state.selectedTabID == id { state.selectedSpaceID = spaceID }  // follow the selected tab to its new Space
        return []
    }

    private static func clearSelection(_ state: inout BrowserState) -> [Effect] {
        state.selectedTabID = nil
        return []
    }

    // MARK: Drag and drop

    /// Moves a node within the selected Space (or a tab to Favorites). Invalid drops change nothing.
    private static func moveNode(_ state: inout BrowserState, _ id: UUID, to destination: NodeDestination, _ env: ReducerEnvironment)
        -> [Effect]
    {
        guard let si = state.selectedSpaceIndex, canMove(state.spaces[si], id, to: destination) else { return [] }
        if case .favorites = destination { return reduceTab(&state, .addToFavorites(id), env) }
        var pinned = state.spaces[si].pinned
        var today = state.spaces[si].today
        guard var node = pinned.removeNode(id: id) ?? today.removeNode(id: id) else { return [] }
        // Pinned tabs remember their home URL; Today tabs don't.
        func adapt(_ toPinned: Bool) {
            if case .tab(var t) = node.kind {
                t.homeURL = toPinned ? (t.homeURL ?? t.url) : nil
                node = .tab(t)
            }
        }
        var placed = false
        switch destination {
        case .before(let target):
            if pinned.containsNode(target) {
                adapt(true)
                placed = pinned.insertNode(node, before: target)
            } else if today.containsNode(target) {
                adapt(false)
                placed = today.insertNode(node, before: target)
            }
        case .endOf(let section):
            adapt(section == .pinned)
            if section == .pinned { pinned.append(node) } else { today.append(node) }
            placed = true
        case .intoFolder(let folderID):
            let inPinned = pinned.containsNode(folderID)
            adapt(inPinned)
            placed = inPinned ? pinned.appendNode(node, toFolder: folderID) : today.appendNode(node, toFolder: folderID)
        case .favorites:
            placed = false
        }
        guard placed else { return [] }  // nothing changes when the drop target vanished
        state.spaces[si].pinned = pinned
        state.spaces[si].today = today
        return []
    }

    /// A drop is valid when the item is in the Space and wouldn't land in itself (folders into their own subfolders).
    private static func canMove(_ space: Space, _ id: UUID, to destination: NodeDestination) -> Bool {
        guard space.pinned.containsNode(id) || space.today.containsNode(id) else { return false }
        if case .before(let target) = destination, target == id { return false }
        guard case .folder(let folder)? = (space.pinned + space.today).first(where: { $0.id == id })?.kind else { return true }
        switch destination {
        case .intoFolder(let target): return target != id && !folder.children.containsNode(target)
        case .before(let target): return !folder.children.containsNode(target)
        case .favorites: return false
        case .endOf: return true
        }
    }

    // MARK: Split View

    /// Moves `other` into `id`'s split (both in the selected Space; at most 4 tabs per split).
    private static func splitWith(_ state: inout BrowserState, _ id: UUID, other: UUID) -> [Effect] {
        guard id != other, let si = state.selectedSpaceIndex else { return [] }
        let space = state.spaces[si]
        let inSpace = (space.pinned + space.today).flatMap(\.tabs).map(\.id)
        guard inSpace.contains(id), inSpace.contains(other) else { return [] }
        let existing = space.pinned.split(containing: id) ?? space.today.split(containing: id)
        if let existing, existing.tabs.count >= 4 || existing.tabs.contains(where: { $0.id == other }) { return [] }
        guard let moving = state.spaces[si].pinned.removeTab(id: other) ?? state.spaces[si].today.removeTab(id: other) else { return [] }
        if !state.spaces[si].pinned.addToSplit(tabID: id, moving) { _ = state.spaces[si].today.addToSplit(tabID: id, moving) }
        return []
    }

    /// Applies a split edit to both sections of the selected Space.
    private static func editSplits(_ state: inout BrowserState, _ edit: (inout [Node]) -> Bool) -> [Effect] {
        guard let si = state.selectedSpaceIndex else { return [] }
        if !edit(&state.spaces[si].pinned) { _ = edit(&state.spaces[si].today) }
        return []
    }

    // MARK: Opening

    private static func open(_ state: inout BrowserState, _ url: URL, _ disposition: TabAction.Disposition, _ env: ReducerEnvironment)
        -> [Effect]
    {
        if disposition == .currentTab, let id = state.selectedTabID, state.tab(withID: id) != nil {
            mutateTab(&state, id) {
                $0.url = url
                $0.lastActiveAt = env.now()
            }
            return [.load(tabID: id, url: url)]
        }
        guard let si = state.selectedSpaceIndex else { return [] }
        let tab = Tab(id: env.uuid(), url: url, lastActiveAt: env.now())
        if disposition == .splitWithCurrent, let current = state.selectedTabID,
            state.spaces[si].pinned.addToSplit(tabID: current, tab) || state.spaces[si].today.addToSplit(tabID: current, tab)
        {
            state.selectedTabID = tab.id
            return [.load(tabID: tab.id, url: url)]
        }
        state.spaces[si].today.insert(.tab(tab), at: 0)
        state.selectedTabID = tab.id
        return [.load(tabID: tab.id, url: url)]
    }

    /// Child pages are already loading in the engine, so no `.load` effect.
    private static func openChild(
        _ state: inout BrowserState, id: UUID, url: URL?, openerID: UUID, select: Bool, _ env: ReducerEnvironment
    ) -> [Effect] {
        guard state.tab(withID: id) == nil else { return [] }
        var spaceID = state.selectedSpaceID
        if case .space(let sid, _)? = state.locate(openerID)?.location { spaceID = sid }
        guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
        let tab = Tab(id: id, url: url, lastActiveAt: env.now())
        state.spaces[si].today.insert(.tab(tab), at: 0)
        if select {
            state.selectedSpaceID = state.spaces[si].id
            state.selectedTabID = id
        }
        return []
    }

    // MARK: Selection

    private static func select(_ state: inout BrowserState, _ id: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard let (_, location) = state.locate(id) else { return [] }
        if case .space(let spaceID, _) = location { state.selectedSpaceID = spaceID }
        mutateTab(&state, id) { $0.lastActiveAt = env.now() }
        state.selectedTabID = id
        return []
    }

    private static func selectAdjacent(_ state: inout BrowserState, _ offset: Int, _ env: ReducerEnvironment) -> [Effect] {
        guard let space = state.selectedSpace else { return [] }
        let tabs = state.orderedTabs(in: space)
        guard !tabs.isEmpty else { return [] }
        let current = state.selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? -1
        let next = ((current + offset) % tabs.count + tabs.count) % tabs.count
        return select(&state, tabs[next].id, env)
    }

    // MARK: Closing

    /// ⌘W. Pinned tabs and favorites stay in the sidebar (only the page is freed); Today tabs are archived.
    private static func close(_ state: inout BrowserState, _ id: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard let (_, location) = state.locate(id) else { return [] }
        let neighbor = neighborForSelection(state, closing: id)
        switch location {
        case .favorite, .space(_, .pinned):
            if state.selectedTabID == id { state.selectedTabID = neighbor }
            return [.discardPage(tabID: id)]
        case .space(let spaceID, .today):
            guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }),
                let tab = state.spaces[si].today.removeTab(id: id)
            else { return [] }
            let archived = ArchivedTab(tab: tab, spaceID: spaceID, archivedAt: env.now())
            pushArchive(&state, archived)
            state.recentlyClosed.insert(archived, at: 0)
            state.recentlyClosed = Array(state.recentlyClosed.prefix(BrowserState.recentlyClosedLimit))
            if state.selectedTabID == id { state.selectedTabID = neighbor }
            return [.discardPage(tabID: id)]
        }
    }

    private static func restoreLastClosed(_ state: inout BrowserState, _ env: ReducerEnvironment) -> [Effect] {
        guard !state.recentlyClosed.isEmpty else { return [] }
        let item = state.recentlyClosed.removeFirst()
        state.archive.removeAll { $0.id == item.id }
        guard let si = state.spaces.firstIndex(where: { $0.id == item.spaceID }) ?? state.selectedSpaceIndex else { return [] }
        var tab = item.tab
        tab.lastActiveAt = env.now()
        state.spaces[si].today.insert(.tab(tab), at: 0)
        state.selectedSpaceID = state.spaces[si].id
        state.selectedTabID = tab.id
        return tab.url.map { [.load(tabID: tab.id, url: $0)] } ?? []
    }

    /// After closing the selected tab, select the tab above it (or below if it was first).
    private static func neighborForSelection(_ state: BrowserState, closing id: UUID) -> UUID? {
        guard state.selectedTabID == id, let space = state.selectedSpace else { return state.selectedTabID }
        let tabs = state.orderedTabs(in: space)
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        if i > 0 { return tabs[i - 1].id }
        return tabs.count > 1 ? tabs[1].id : nil
    }

    // MARK: Pinning & favorites

    private static func togglePin(_ state: inout BrowserState, _ id: UUID) -> [Effect] {
        guard let (tab, location) = state.locate(id) else { return [] }
        switch location {
        case .space(let spaceID, .today):
            guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
            _ = state.spaces[si].today.removeTab(id: id)
            var pinned = tab
            pinned.homeURL = tab.url
            state.spaces[si].pinned.append(.tab(pinned))
        case .space(let spaceID, .pinned):
            guard let si = state.spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
            _ = state.spaces[si].pinned.removeTab(id: id)
            state.spaces[si].today.insert(.tab(unpinned(tab)), at: 0)
        case .favorite(let profileID):
            guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }),
                let si = state.selectedSpaceIndex
            else { return [] }
            state.profiles[pi].favorites.removeAll { $0.id == id }
            state.spaces[si].today.insert(.tab(unpinned(tab)), at: 0)
        }
        return []
    }

    private static func unpinned(_ tab: Tab) -> Tab {
        var copy = tab
        copy.homeURL = nil
        return copy
    }

    private static func resetToHome(_ state: inout BrowserState, _ id: UUID) -> [Effect] {
        guard let tab = state.tab(withID: id), let home = tab.homeURL else { return [] }
        mutateTab(&state, id) { $0.url = home }
        return [.load(tabID: id, url: home)]
    }

    private static func addToFavorites(_ state: inout BrowserState, _ id: UUID) -> [Effect] {
        guard let profileID = state.selectedSpace?.profileID,
            let pi = state.profiles.firstIndex(where: { $0.id == profileID }),
            let tab = removeTabAnywhere(&state, id)
        else { return [] }
        var fav = tab
        fav.homeURL = fav.homeURL ?? fav.url
        state.profiles[pi].favorites.append(fav)
        return []
    }

    // MARK: Updates & moves

    private static func didUpdate(_ state: inout BrowserState, _ id: UUID, url: URL?, title: String?) -> [Effect] {
        mutateTab(&state, id) { tab in
            if let url { tab.url = url }
            if let title, !title.isEmpty { tab.title = title }
        }
        return []
    }

    private static func move(_ state: inout BrowserState, _ id: UUID, section: Section, index: Int) -> [Effect] {
        guard let si = state.selectedSpaceIndex, let tab = removeTabAnywhere(&state, id) else { return [] }
        var moved = tab
        moved.homeURL = section == .pinned ? (tab.homeURL ?? tab.url) : nil
        switch section {
        case .pinned: state.spaces[si].pinned.insert(.tab(moved), at: min(max(index, 0), state.spaces[si].pinned.count))
        case .today: state.spaces[si].today.insert(.tab(moved), at: min(max(index, 0), state.spaces[si].today.count))
        }
        return []
    }
}
