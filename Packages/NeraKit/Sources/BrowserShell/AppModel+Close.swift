// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
#endif

extension AppModel {
    /// ⌘W: the command bar if it's open, otherwise the selected tab; an empty private window closes (even with its
    /// command bar showing, as it opens).
    public func closeFrontmost() {
        let isEmptyPrivateWindow = isPrivate && state.selectedTabID == nil
        if isCommandBarPresented && !isEmptyPrivateWindow {
            dismissCommandBar()
        } else if state.selectedTabID != nil {
            closeSelectedTab()
        } else if isPrivate {
            #if os(macOS)
                NSApp.keyWindow?.performClose(nil)
            #endif
        }
    }
}
