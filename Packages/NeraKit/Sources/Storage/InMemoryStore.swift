// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import Foundation

/// Keeps the library in memory only. Used by UI tests (`NERA_UI_TEST=1`) and previews, so automated
/// runs never read or write the user's real library (PRV-008).
public final class InMemoryStore: StatePersisting, @unchecked Sendable {
    // @unchecked: all access to `stored` goes through `lock`.
    private let lock = NSLock()
    private var stored: BrowserState?

    /// Creates a store, optionally pre-filled.
    public init(_ initial: BrowserState? = nil) { stored = initial }

    /// Returns the stored library.
    public func load() throws -> BrowserState? { lock.withLock { stored } }

    /// Replaces the stored library.
    public func save(_ state: BrowserState) throws { lock.withLock { stored = state } }
}
