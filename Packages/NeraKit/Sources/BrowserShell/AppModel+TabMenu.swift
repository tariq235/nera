// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import Foundation

/// What the tab menu (a Favorite's, a pinned tab's or a Today tab's) does beyond library actions.
extension AppModel {
    /// Whether the tab's page is playing sound, and whether it's muted.
    public func audio(of tabID: UUID) -> (playing: Bool, muted: Bool) {
        guard let page = pages.existingPage(for: tabID) else { return (false, state.tab(withID: tabID)?.isMuted ?? false) }
        return (page.state.isAudible, page.state.isMuted)
    }

    /// Mutes or unmutes the tab's page.
    public func toggleMute(_ tabID: UUID) {
        let page = pages.existingPage(for: tabID)
        let muted = !(page?.state.isMuted ?? state.tab(withID: tabID)?.isMuted ?? false)
        page?.setMuted(muted)
        send(.tab(.setMuted(tabID, muted)))
    }

    /// Selects the tab and opens Customize Page (the site's fonts and colors).
    public func customizePage(_ tabID: UUID) {
        send(.tab(.select(tabID)))
        isSiteStyleEditorPresented = true
    }

    /// Selects the tab and opens the command bar to add a page beside it in Split View.
    public func addSplitView(_ tabID: UUID) {
        send(.tab(.select(tabID)))
        showCommandBar(.splitWithCurrent)
    }

    /// The page in Peek while one is open, else the selected tab's: the address pill always shows the site on screen.
    public var addressURL: URL? { peekPage?.state.url ?? state.selectedTab?.url }

    /// The page open in Peek from this tab: its address and icon, shown small on the tab's tile.
    public func peekOpened(from tabID: UUID) -> (url: URL?, png: Data?)? {
        guard let peek, peek.openerID == tabID else { return nil }
        let page = pages.existingPage(for: peek.id)
        let url = page?.state.url
        return (url, page?.state.favicon ?? url.flatMap(favicon(forURL:)))
    }
}
