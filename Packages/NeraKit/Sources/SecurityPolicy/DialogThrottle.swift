// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Stops a page from trapping the user with an endless stream of `alert`/`confirm`/`prompt`
/// dialogs (SR-041). After `limit` dialogs within `window`, further dialogs are auto-cancelled until
/// the page navigates again.
public struct DialogThrottle: Sendable, Equatable {
    /// Dialogs allowed per window.
    public let limit: Int
    /// Length of the sliding window.
    public let window: TimeInterval
    /// `true` once the page exceeded the limit; stays set until ``reset()``.
    public private(set) var isSuppressed = false
    private var shown: [Date] = []

    /// Creates a throttle. Defaults: 3 dialogs per 5 seconds.
    public init(limit: Int = 3, window: TimeInterval = 5) {
        self.limit = limit
        self.window = window
    }

    /// Records a dialog request at `now` and returns whether it may be shown.
    public mutating func shouldShow(at now: Date) -> Bool {
        if isSuppressed { return false }
        shown.removeAll { now.timeIntervalSince($0) > window }
        guard shown.count < limit else {
            isSuppressed = true
            return false
        }
        shown.append(now)
        return true
    }

    /// Clears the history, e.g. after the page commits a new navigation.
    public mutating func reset() {
        shown.removeAll()
        isSuppressed = false
    }
}
