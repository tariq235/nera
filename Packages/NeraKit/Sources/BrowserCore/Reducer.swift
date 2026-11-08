// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The single place where `BrowserState` changes.
///
/// `reduce` is a pure function: given the same state, action and environment it always produces the
/// same new state and effects. Each domain lives in its own file (`Reducer+Tabs`, `Reducer+Spaces`,
/// `Reducer+Library`).
public enum Reducer {
    /// Applies `action` to `state` and returns the side effects the engine layer must perform.
    public static func reduce(_ state: inout BrowserState, _ action: Action, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .tab(let a): reduceTab(&state, a, env)
        case .space(let a): reduceSpace(&state, a, env)
        case .library(let a): reduceLibrary(&state, a, env)
        }
    }

    // MARK: Shared helpers

    static func mutateTab(_ state: inout BrowserState, _ id: UUID, _ transform: (inout Tab) -> Void) {
        for pi in state.profiles.indices {
            if let fi = state.profiles[pi].favorites.firstIndex(where: { $0.id == id }) {
                transform(&state.profiles[pi].favorites[fi])
                return
            }
        }
        for si in state.spaces.indices {
            if state.spaces[si].pinned.updateTab(id: id, transform) { return }
            if state.spaces[si].today.updateTab(id: id, transform) { return }
        }
    }

    static func removeTabAnywhere(_ state: inout BrowserState, _ id: UUID) -> Tab? {
        for pi in state.profiles.indices {
            if let fi = state.profiles[pi].favorites.firstIndex(where: { $0.id == id }) {
                return state.profiles[pi].favorites.remove(at: fi)
            }
        }
        for si in state.spaces.indices {
            if let t = state.spaces[si].pinned.removeTab(id: id) { return t }
            if let t = state.spaces[si].today.removeTab(id: id) { return t }
        }
        return nil
    }

    static func pushArchive(_ state: inout BrowserState, _ item: ArchivedTab) {
        state.archive.insert(item, at: 0)
        if state.archive.count > BrowserState.archiveLimit {
            state.archive.removeLast(state.archive.count - BrowserState.archiveLimit)
        }
    }
}
