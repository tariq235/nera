// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
public import Observation

/// Persists the library. Implemented by `Storage` (JSON on disk, in-memory for tests and UI tests).
public protocol StatePersisting: Sendable {
    /// Loads the saved library, or `nil` if there is none (or it was unreadable and set aside).
    func load() throws -> BrowserState?
    /// Saves the library atomically.
    func save(_ state: BrowserState) throws
}

/// Single source of truth for the UI. All changes go through `send(_:)` → `Reducer.reduce`.
@MainActor
@Observable
public final class BrowserStore {
    /// The current library. Read-only outside the store; change it with `send(_:)`.
    public private(set) var state: BrowserState

    @ObservationIgnored private let env: ReducerEnvironment
    @ObservationIgnored private let persistence: (any StatePersisting)?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// Receives every effect the reducer produces (wired to the engine layer by the shell).
    @ObservationIgnored public var effectHandler: ((Effect) -> Void)?

    /// Saves are debounced so rapid tab updates (titles changing while loading) don't hammer the disk.
    @ObservationIgnored public var saveDebounce: Duration = .milliseconds(400)

    /// Creates a store around an existing state.
    public init(state: BrowserState, env: ReducerEnvironment = .live, persistence: (any StatePersisting)? = nil) {
        self.state = state
        self.env = env
        self.persistence = persistence
    }

    /// Loads persisted state, or creates a fresh library if there is none, then archives stale tabs.
    public static func load(persistence: any StatePersisting, env: ReducerEnvironment = .live) -> BrowserStore {
        let loaded = try? persistence.load()
        let store = BrowserStore(state: loaded ?? .initial(uuid: env.uuid), env: env, persistence: persistence)
        store.send(.library(.archiveSweep))
        return store
    }

    /// Applies an action, schedules a save and forwards resulting effects to `effectHandler`.
    public func send(_ action: Action) {
        let effects = Reducer.reduce(&state, action, env)
        scheduleSave()
        for effect in effects { effectHandler?(effect) }
    }

    /// Writes immediately, e.g. when the app quits or moves to the background.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        try? persistence?.save(state)
    }

    private func scheduleSave() {
        guard persistence != nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDebounce] in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled, let self else { return }
            try? self.persistence?.save(self.state)
        }
    }
}
