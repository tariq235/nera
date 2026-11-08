// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import Foundation

/// Deterministic clock and UUIDs for reducer and lifecycle tests.
public final class TestEnv: @unchecked Sendable {
    // @unchecked: `counter` is guarded by `lock`; `now` is only mutated by the test itself.
    /// The current fake time. Advance it with `now += seconds`.
    public var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var counter = 0
    private let lock = NSLock()

    /// Creates an environment at a fixed time.
    public init() {}

    /// Sequential, readable UUIDs: `…000001`, `…000002`, …
    public func nextUUID() -> UUID {
        lock.withLock {
            counter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
        }
    }

    /// A reducer environment backed by this clock and UUID sequence.
    public var reducer: ReducerEnvironment {
        ReducerEnvironment(now: { self.now }, uuid: { self.nextUUID() })
    }
}
