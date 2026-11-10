// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import Foundation

/// What the sidebar needs from the app. Keeps the Sidebar module independent of the shell, the
/// engine and storage: it's a view over `BrowserState` plus intents.
@MainActor
public protocol SidebarHost: AnyObject {
    /// The library to display.
    var state: BrowserState { get }
    /// Sends an action to the store.
    func send(_ action: Action)
    /// Opens the command bar (⌘T new tab, ⌘L current tab).
    func showCommandBar(_ disposition: TabAction.Disposition)
    /// The tab's site icon (PNG), from its live page or the icon cache.
    func favicon(for tab: BrowserCore.Tab) -> Data?
    /// The cached icon of a site (a Favorite's own site while its page is elsewhere).
    func favicon(forURL url: URL) -> Data?
    /// Starts the "Import from Arc" flow.
    func requestArcImport()
    /// Back, forward and loading state of the selected tab's page.
    var pageNavigation: PageNavigation { get }
    /// Goes back in the selected tab.
    func goBack()
    /// Goes forward in the selected tab.
    func goForward()
    /// Reloads the selected tab.
    func reload()
    /// Hides or shows the sidebar (⌘S).
    func toggleSidebar()
    /// Moves keyboard focus into the current page (Return in the sidebar).
    func focusPage()
    /// Opens the Edit Space sheet (name, icon and colors).
    func editSpace(_ id: UUID)
    /// The Space's colors in Arc, when it was imported from Arc and Arc's data is still on this Mac.
    func arcTheme(for spaceID: UUID) -> SpaceTheme?
    /// Whether the tab's page is playing sound, and whether it's muted (the tab menu's Mute).
    func audio(of tabID: UUID) -> (playing: Bool, muted: Bool)
    /// Mutes or unmutes the tab's page.
    func toggleMute(_ tabID: UUID)
    /// Opens the tab and its Customize Page panel (fonts and colors for the site).
    func customizePage(_ tabID: UUID)
    /// Opens the tab with the command bar ready to add a page beside it in Split View.
    func addSplitView(_ tabID: UUID)
    /// The address the address pill shows: the page in Peek while one is open (a page always shows its site), else
    /// the selected tab's.
    var addressURL: URL? { get }
    /// The page open in Peek from this tab, for the small icon on the tab's tile.
    func peekOpened(from tabID: UUID) -> (url: URL?, png: Data?)?
    /// + New Space: makes a Space and opens New Space to name and style it.
    func newSpace()
    /// How far a two-finger swipe on the sidebar has dragged the Space sideways (points; 0 when idle).
    var spaceSwipeOffset: CGFloat { get }
    /// A private window: one list of private tabs, no Spaces, Favorites or pinned tabs.
    var isPrivateSession: Bool { get }
    /// The page is showing full screen (a video): the sidebar slides in over it and offers to leave.
    var isPageFullscreen: Bool { get }
    /// Leaves the page's full screen.
    func exitPageFullscreen()
}

/// What the sidebar's navigation buttons show.
public struct PageNavigation: Equatable, Sendable {
    /// Back is possible.
    public var canGoBack: Bool
    /// Forward is possible.
    public var canGoForward: Bool
    /// The page is loading.
    public var isLoading: Bool

    /// Creates the state.
    public init(canGoBack: Bool = false, canGoForward: Bool = false, isLoading: Bool = false) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}

extension SidebarHost {
    /// Not private unless the host says so.
    public var isPrivateSession: Bool { false }
    /// No full screen unless the host says so.
    public var isPageFullscreen: Bool { false }
    /// Nothing to leave by default.
    public func exitPageFullscreen() {}
    /// No cached icons by default.
    public func favicon(forURL url: URL) -> Data? { nil }
    /// No Arc colors unless the host has them.
    public func arcTheme(for spaceID: UUID) -> SpaceTheme? { nil }
    /// Silent unless the host knows better.
    public func audio(of tabID: UUID) -> (playing: Bool, muted: Bool) { (false, false) }
    /// Nothing to mute by default.
    public func toggleMute(_ tabID: UUID) {}
    /// No page styles by default.
    public func customizePage(_ tabID: UUID) {}
    /// No Split View by default.
    public func addSplitView(_ tabID: UUID) {}
    /// The selected tab's address unless the host shows another page.
    public var addressURL: URL? { state.selectedTab?.url }
    /// No Peek by default.
    public func peekOpened(from tabID: UUID) -> (url: URL?, png: Data?)? { nil }
}
