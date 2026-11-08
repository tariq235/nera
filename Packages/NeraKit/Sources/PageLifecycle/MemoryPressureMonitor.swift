// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Dispatch

/// How urgently the system needs memory back.
public enum MemoryPressureLevel: Sendable, Equatable {
    /// Free what's cheap to restore (half of the background pages).
    case warning
    /// Free everything except the page the user is looking at.
    case critical
}

/// Delivers system memory-pressure notifications (macOS and iOS) on the main actor.
@MainActor
public final class MemoryPressureMonitor {
    private var source: (any DispatchSourceMemoryPressure)?

    /// Creates a monitor. Call ``start(_:)`` to begin listening.
    public init() {}

    /// Starts listening. Replaces any previous handler.
    public func start(_ handler: @escaping @MainActor @Sendable (MemoryPressureLevel) -> Void) {
        stop()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : .warning
            MainActor.assumeIsolated { handler(level) }
        }
        source.resume()
        self.source = source
    }

    /// Stops listening.
    public func stop() {
        source?.cancel()
        source = nil
    }
}
