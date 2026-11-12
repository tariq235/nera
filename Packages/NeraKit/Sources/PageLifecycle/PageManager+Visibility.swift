// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Which pages are on screen, and freeing the others under memory pressure or when idle.
extension PageManager {
    /// Records which tabs a browser window shows (its selected tab and Split View panes; an empty set when it
    /// closes). A page shown in any window is never evicted or suspended.
    public func setShownTabs(_ ids: Set<UUID>, by window: ObjectIdentifier) {
        let before = visibleTabIDs
        shownTabs[window] = ids.isEmpty ? nil : ids
        let after = visibleTabIDs
        if before != after { visibilityChanged(before.subtracting(after), after.subtracting(before)) }
    }

    /// Tabs on screen in any window.
    public var visibleTabIDs: Set<UUID> { shownTabs.values.reduce(into: []) { $0.formUnion($1) } }

    /// Frees memory: `.warning` discards the older half of the background pages, `.critical` all of them.
    public func handleMemoryPressure(_ level: MemoryPressureLevel) {
        let background = backgroundPagesOldestFirst()
        let count = level == .critical ? background.count : background.count / 2 + background.count % 2
        background.prefix(count).forEach(discard)
    }

    /// Discards background pages unused for longer than ``idleTimeout``.
    public func suspendIdlePages(now: Date? = nil) {
        let now = now ?? clock()
        for id in backgroundPagesOldestFirst() where now.timeIntervalSince(lastUsed[id] ?? now) > idleTimeout {
            discard(id)
        }
    }

    func backgroundPagesOldestFirst() -> [UUID] {
        pages.keys.filter { $0 != activeTabID && !visibleTabIDs.contains($0) && !keptPageIDs.contains($0) }.sorted {
            (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast)
        }
    }
}
