// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import Foundation
import Import
public import Sidebar

#if os(macOS)
    import AppKit
#endif

// Sidebar navigation, Edit Space and the welcome screen.
extension AppModel {
    /// Back, forward and loading state of the selected tab.
    public var pageNavigation: PageNavigation {
        guard let page = selectedPage else { return PageNavigation() }
        return PageNavigation(canGoBack: page.state.canGoBack, canGoForward: page.state.canGoForward, isLoading: page.state.isLoading)
    }

    /// The colors behind the window: the Space's, blended toward its neighbor while a swipe drags between them.
    public var displayedTheme: SpaceTheme? {
        guard let current = state.selectedSpace?.theme else { return nil }
        let ids = state.spaces.map(\.id)
        guard spaceSwipeOffset != 0, let i = ids.firstIndex(of: state.selectedSpaceID) else { return current }
        let j = spaceSwipeOffset < 0 ? i + 1 : i - 1
        guard state.spaces.indices.contains(j) else { return current }
        return current.blended(toward: state.spaces[j].theme, by: min(1, abs(spaceSwipeOffset) / 260))
    }

    /// ⌘S.
    public func toggleSidebar() { isSidebarVisible.toggle() }

    /// Gives the current page keyboard focus (Return in the sidebar).
    public func focusPage() {
        #if os(macOS)
            guard let view = selectedPage?.view, let window = view.window else { return }
            // The engine's own view is the deepest one that accepts focus (Chromium's or WebKit's).
            let target = view.subviews.last(where: \.acceptsFirstResponder) ?? view.subviews.first ?? view
            window.makeFirstResponder(target)
        #endif
    }

    /// Opens the Edit Space sheet.
    public func editSpace(_ id: UUID) { editingSpaceID = id }

    /// The welcome screen shows on the first launch (never in private windows).
    public var isWelcomePresented: Bool { !state.settings.hasCompletedOnboarding && !isPrivate }

    /// Whether Arc's sidebar file is on this Mac (for one-click import).
    public var isArcInstalled: Bool {
        #if os(macOS)
            FileManager.default.isReadableFile(atPath: ArcImporter.defaultSidebarURL.path)  // naming: import-reference
        #else
            false
        #endif
    }

    /// Imports Arc's Spaces straight from where Arc keeps them, then closes the welcome screen.
    public func importArcFromDefaultLocation() {
        #if os(macOS)
            importArcSidebar(from: ArcImporter.defaultSidebarURL)  // naming: import-reference
        #endif
        finishWelcome()
    }

    /// Start fresh: adds the picked sites as Favorites and, optionally, a Work Space.
    public func startFresh(favorites: [URL], addWorkSpace: Bool, finish: Bool = true) {
        guard let profile = state.currentProfile else {
            if finish { finishWelcome() }
            return
        }
        let tabs = favorites.map { Tab(id: UUID(), url: $0, homeURL: $0, lastActiveAt: Date()) }
        let current = state.selectedSpaceID
        if !tabs.isEmpty { send(.library(.importLibrary(spaces: [], favorites: tabs))) }
        if addWorkSpace {
            send(.space(.createInProfile(title: "Work", profileID: profile.id)))
            send(.space(.select(current)))
        }
        if finish { finishWelcome() }
    }

    /// Closes the welcome screen for good.
    public func finishWelcome() { send(.library(.completeOnboarding)) }

    /// The most visited sites in the current profile, for the start page (none in private windows).
    public var topSites: [(url: URL, title: String)] {
        guard !isPrivate, let profile = state.currentProfile else { return [] }
        return (history?.topSites(profileID: profile.id, limit: 8) ?? []).map { ($0.url, $0.title) }
    }

    /// The cached icon for a site.
    public func favicon(forURL url: URL) -> Data? { url.host().flatMap(favicons.icon(forHost:)) }
}
