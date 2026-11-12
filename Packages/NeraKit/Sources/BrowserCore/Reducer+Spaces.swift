// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

extension Reducer {
    static func reduceSpace(_ state: inout BrowserState, _ action: SpaceAction, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .create(let title):
            guard let profileID = state.selectedSpace?.profileID ?? state.profiles.first?.id else { return [] }
            return createSpace(&state, title: title, profileID: profileID, env)

        case .createInProfile(let title, let profileID): return createSpace(&state, title: title, profileID: profileID, env)
        case .setProfile(let id, let profileID): return setProfile(&state, space: id, profileID: profileID)

        case .select(let id):
            guard let space = state.spaces.first(where: { $0.id == id }) else { return [] }
            state.selectedSpaceID = id
            state.selectedTabID = state.orderedTabs(in: space).max { $0.lastActiveAt < $1.lastActiveAt }?.id
            return []

        case .selectAdjacent(let offset):
            guard let i = state.selectedSpaceIndex, !state.spaces.isEmpty else { return [] }
            let n = state.spaces.count
            return reduceSpace(&state, .select(state.spaces[((i + offset) % n + n) % n].id), env)

        case .rename(let id, let title):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let i = state.spaces.firstIndex(where: { $0.id == id }) else { return [] }
            state.spaces[i].title = trimmed
            return []

        case .delete(let id): return deleteSpace(&state, id, env)

        case .customize(let id, let icon, let theme): return customizeSpace(&state, id, icon: icon, theme: theme)

        case .createFolder, .toggleFolder, .renameFolder, .deleteFolder, .togglePinnedSection: return reduceSections(&state, action, env)

        case .clearToday: return clearToday(&state, env)
        }
    }

    /// Folders, and folding the pinned section.
    private static func reduceSections(_ state: inout BrowserState, _ action: SpaceAction, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .createFolder(let title):
            guard let si = state.selectedSpaceIndex else { return [] }
            state.spaces[si].pinned.append(Node(id: env.uuid(), kind: .folder(Folder(title: title))))
            return []

        case .toggleFolder(let id):
            guard let si = state.selectedSpaceIndex else { return [] }
            if !state.spaces[si].pinned.updateFolder(id: id, { $0.isExpanded.toggle() }) {
                state.spaces[si].today.updateFolder(id: id) { $0.isExpanded.toggle() }
            }
            return []
        case .renameFolder(let id, let title): return renameFolder(&state, id, title: title)
        case .deleteFolder(let id): return deleteFolder(&state, id)
        case .togglePinnedSection(let id):
            if let i = state.spaces.firstIndex(where: { $0.id == id }) {
                state.spaces[i].pinnedFold = state.spaces[i].isPinnedCollapsed ? .open : .folded
            }
            return []
        default: return []
        }
    }

    private static func clearToday(_ state: inout BrowserState, _ env: ReducerEnvironment) -> [Effect] {
        guard let si = state.selectedSpaceIndex else { return [] }
        let tabs = state.spaces[si].today.flatMap(\.tabs)
        guard !tabs.isEmpty else { return [] }
        state.clearedToday = ClearedToday(spaceID: state.spaces[si].id, nodes: state.spaces[si].today, clearedAt: env.now())
        state.spaces[si].today = []
        for tab in tabs { pushArchive(&state, ArchivedTab(tab: tab, spaceID: state.spaces[si].id, archivedAt: env.now())) }
        if let sel = state.selectedTabID, tabs.contains(where: { $0.id == sel }) { state.selectedTabID = nil }
        return tabs.map { .discardPage(tabID: $0.id) }
    }

    // MARK: Profiles

    private static func customizeSpace(_ state: inout BrowserState, _ id: UUID, icon: SpaceIcon?, theme: SpaceTheme?) -> [Effect] {
        guard let i = state.spaces.firstIndex(where: { $0.id == id }) else { return [] }
        if let icon { state.spaces[i].icon = icon }
        if let theme { state.spaces[i].theme = theme.clamped }
        return []
    }

    private static func createSpace(_ state: inout BrowserState, title: String, profileID: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard state.profiles.contains(where: { $0.id == profileID }) else { return [] }
        // Each new Space gets the next color and icon, so Spaces are easy to tell apart.
        let look = SpaceTheme.palette[state.spaces.count % SpaceTheme.palette.count]
        let space = Space(id: env.uuid(), title: title, icon: look.icon, theme: look.theme, profileID: profileID)
        state.spaces.append(space)
        state.selectedSpaceID = space.id
        state.selectedTabID = nil
        return []
    }

    private static func setProfile(_ state: inout BrowserState, space id: UUID, profileID: UUID) -> [Effect] {
        guard state.profiles.contains(where: { $0.id == profileID }),
            let si = state.spaces.firstIndex(where: { $0.id == id }), state.spaces[si].profileID != profileID
        else { return [] }
        state.spaces[si].profileID = profileID
        // Pages hold the old profile's cookies: discard them so they reopen in the new profile.
        return (state.spaces[si].pinned + state.spaces[si].today).flatMap(\.tabs).map { .discardPage(tabID: $0.id) }
    }

    /// Removes a folder but keeps its contents, in its place.
    private static func deleteFolder(_ state: inout BrowserState, _ id: UUID) -> [Effect] {
        guard let si = state.selectedSpaceIndex else { return [] }
        func unwrap(_ nodes: inout [Node]) -> Bool {
            if let i = nodes.firstIndex(where: { $0.id == id }), case .folder(let folder) = nodes[i].kind {
                nodes.replaceSubrange(i...i, with: folder.children)
                return true
            }
            for i in nodes.indices {
                if case .folder(var folder) = nodes[i].kind, unwrap(&folder.children) {
                    nodes[i].kind = .folder(folder)
                    return true
                }
            }
            return false
        }
        if !unwrap(&state.spaces[si].pinned) { _ = unwrap(&state.spaces[si].today) }
        return []
    }

    private static func renameFolder(_ state: inout BrowserState, _ id: UUID, title: String) -> [Effect] {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let si = state.selectedSpaceIndex else { return [] }
        if !state.spaces[si].pinned.updateFolder(id: id, { $0.title = name }) {
            state.spaces[si].today.updateFolder(id: id) { $0.title = name }
        }
        return []
    }

    private static func deleteSpace(_ state: inout BrowserState, _ id: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard state.spaces.count > 1, let i = state.spaces.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = state.spaces.remove(at: i)
        let effects = (removed.pinned + removed.today).flatMap(\.tabs).map { Effect.discardPage(tabID: $0.id) }
        if state.selectedSpaceID == id {
            _ = reduceSpace(&state, .select(state.spaces[max(0, i - 1)].id), env)
        }
        return effects
    }
}
