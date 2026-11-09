// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

extension PageManager {
    /// Records which tabs a browser window shows (its selected tab and Split View panes; an empty set when it
    /// closes). A page shown in any window is never evicted or suspended.
    public func setShownTabs(_ ids: Set<UUID>, by window: ObjectIdentifier) {
        shownTabs[window] = ids.isEmpty ? nil : ids
    }

    /// Tabs on screen in any window.
    public var visibleTabIDs: Set<UUID> { shownTabs.values.reduce(into: []) { $0.formUnion($1) } }
}
