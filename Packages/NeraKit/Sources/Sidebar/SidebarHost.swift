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
}
