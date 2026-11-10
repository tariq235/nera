// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import EngineKit
public import Foundation
import PageLifecycle
import SecurityPolicy

/// A link showing in Peek: opened from a Favorite or pinned tab, over the current page.
public struct PeekPage: Equatable, Sendable {
    /// The child page's ID (it becomes the tab's ID if the user keeps it).
    public let id: UUID
    /// The tab that opened it.
    public let openerID: UUID
}

// Peek, Little Windows and Link Rules.
extension AppModel {
    /// The scene ID of Little Windows.
    public static let littleWindowID = "little-window"

    // MARK: Peek

    /// A Favorite or pinned tab opened a link in a new tab: show it in Peek instead (when turned on), so the
    /// tab list stays tidy. Returns whether Peek took it.
    func peekIfWanted(opener: UUID, child: UUID, url: URL?) -> Bool {
        guard state.settings.peekLinks, !isPrivate, peek == nil, let location = state.locate(opener)?.location else { return false }
        switch location {
        case .favorite, .space(_, .pinned): break
        default: return false
        }
        pages.keptPageIDs.insert(child)
        peek = PeekPage(id: child, openerID: opener)
        return true
    }

    /// Whether a clicked link opens in Peek instead of in the tab, like Arc: a Favorite or pinned tab keeps its own
    /// site, so a link that leaves it (another registrable domain) opens over the page. Links within the site, and
    /// links in other tabs, open as usual.
    func linkOpensInPeek(from tabID: UUID, to url: URL) -> Bool {
        guard state.settings.peekLinks, !isPrivate, peek == nil, let location = state.locate(tabID)?.location else { return false }
        switch location {
        case .favorite, .space(_, .pinned): break
        default: return false
        }
        let current = pages.existingPage(for: tabID)?.state.url ?? state.tab(withID: tabID)?.url
        guard let current, let from = SiteEngines.cookieSite(of: current), let to = SiteEngines.cookieSite(of: url) else { return false }
        return from != to
    }

    /// Opens a link in Peek over the tab that clicked it (the link's page is made for Peek; the tab stays put).
    func openInPeek(_ url: URL, from opener: UUID) {
        guard peek == nil, let profile = state.currentProfile else { return }
        let tab = BrowserCore.Tab(id: UUID(), url: url, lastActiveAt: Date())
        pages.keptPageIDs.insert(tab.id)
        _ = pages.page(for: tab, profile: profile, makeActive: false)
        peek = PeekPage(id: tab.id, openerID: opener)
    }

    /// The page showing in Peek.
    public var peekPage: (any WebPage)? { peek.flatMap { pages.existingPage(for: $0.id) } }

    /// Closes Peek; the page goes away.
    public func closePeek() {
        guard let current = peek else { return }
        peek = nil
        pages.keptPageIDs.remove(current.id)
        pages.discard(current.id)
    }

    /// Keeps the Peek page as a tab, next to the tab that opened it (the same live page: nothing reloads).
    public func openPeekAsTab() {
        guard let current = peek, let page = pages.existingPage(for: current.id) else { return }
        peek = nil
        pages.keptPageIDs.remove(current.id)
        adoptAsTab(page, id: current.id, openerID: current.openerID)
    }

    /// Peek's Split View: the page becomes a tab beside a copy of the page that opened it (the Favorite or pinned
    /// tab itself stays where it is). Nothing in Peek reloads.
    public func openPeekInSplitView() {
        guard let current = peek else { return }
        openPeekAsTab()
        send(.tab(.splitBesideCopy(current.id, of: current.openerID)))
    }

    /// Puts a live page that isn't in the tab list (Peek, a Little Window) into the tab list, selected.
    private func adoptAsTab(_ page: any WebPage, id: UUID, openerID: UUID) {
        send(.tab(.openChild(id: id, url: page.state.url, openerID: openerID, select: true)))
        send(.tab(.didUpdate(id, url: page.state.url, title: page.state.title)))
    }

    // MARK: Little Windows

    /// Opens a link in a Little Window: a small window of its own, one click from becoming a tab.
    public func openLittleWindow(_ url: URL) {
        let tab = BrowserCore.Tab(id: UUID(), url: url, lastActiveAt: Date())
        littleTabs[tab.id] = tab
        pages.keptPageIDs.insert(tab.id)
        pendingLittleWindow = tab.id
    }

    /// The page of a Little Window (created and loaded the first time).
    public func littlePage(_ id: UUID) -> (any WebPage)? {
        guard let tab = littleTabs[id], let profile = state.currentProfile else { return pages.existingPage(for: id) }
        return pages.page(for: tab, profile: profile, makeActive: false)
    }

    /// Moves a Little Window's page into the browser as a tab in the current Space (it keeps its state).
    public func moveLittleWindowToBrowser(_ id: UUID) {
        guard littleTabs.removeValue(forKey: id) != nil, let page = pages.existingPage(for: id) else { return }
        pages.keptPageIDs.remove(id)
        adoptAsTab(page, id: id, openerID: state.selectedTabID ?? id)
    }

    /// A Little Window closed: its page goes away (unless it was moved into the browser).
    public func closeLittleWindow(_ id: UUID) {
        guard littleTabs.removeValue(forKey: id) != nil else { return }
        pages.keptPageIDs.remove(id)
        pages.discard(id)
    }

    // MARK: Links from other apps

    /// Opens a link that came from another app: a matching rule's Space, else a Little Window or a new tab in
    /// the current Space (Settings › Links). Private windows never receive these.
    public func openFromOutside(_ url: URL) {
        let trigger: NavigationPolicy.Trigger = url.isFileURL ? .userTyped : .linkClick
        let target: URL
        switch pages.policy.decide(url, trigger: trigger) {
        case .allow: target = url
        case .upgrade(let upgraded): target = upgraded
        case .block(let reason):
            pages.lastBlocked = BlockedNavigation(url: url, reason: reason, tabID: state.selectedTabID ?? UUID())
            return
        case .askToOpenExternally: return  // another app's scheme: not Nera's to open
        }
        switch LinkDestination.of(target, in: state) {
        case .space(let spaceID):
            send(.space(.select(spaceID)))
            openTabNow(target)
        case .littleWindow where !isWelcomePresented:
            openLittleWindow(target)
        default:
            openTabNow(target)
        }
    }

    /// Opens a link in a new tab and starts loading it at once, even if another link arrives before the tab is
    /// drawn (several links sent together each load, like in other browsers).
    private func openTabNow(_ url: URL) {
        send(.tab(.open(url, .newTab)))
        if let tab = state.selectedTab, let profile = state.profile(forTab: tab.id) ?? state.currentProfile {
            _ = pages.page(for: tab, profile: profile)
        }
    }
}
