// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import EngineKit
import Foundation
import Observation

#if os(macOS)
    import AppKit
#endif

/// A browser window's own Space and tab (ADR-0013).
struct WindowSelection: Equatable {
    var spaceID: UUID
    var tabID: UUID?
}

/// Safe Browsing state shared by every browser window, so a warning shows whichever window shows the page.
@MainActor
@Observable
final class SafetyBox {
    var state = SafeBrowsingState()
}

extension AppModel {
    /// Phishing and malware protection (AppModel+SafeBrowsing.swift), shared by all browser windows.
    public var safety: SafeBrowsingState {
        get { safetyBox.state }
        set { safetyBox.state = newValue }
    }

    /// The library, with this window's selected Space and tab.
    public var state: BrowserState {
        guard let selection, store.state.spaces.contains(where: { $0.id == selection.spaceID }) else { return store.state }
        var state = store.state
        state.selectedSpaceID = selection.spaceID
        state.selectedTabID = selection.tabID
        return state
    }

    /// Sends an action to the library, for this window (see `selection`).
    public func send(_ action: Action) {
        // Then the pages learn which tabs this window shows now (Picture in Picture, memory).
        defer { registerShownTabs() }
        guard let selection else { return store.send(action) }
        // Several windows share the library: act on this window's Space and tab, then keep where it lands.
        store.restoreSelection(spaceID: selection.spaceID, tabID: selection.tabID)
        store.send(action)
        self.selection = WindowSelection(spaceID: store.state.selectedSpaceID, tabID: store.state.selectedTabID)
    }

    /// The selected page is showing full screen (a video's full-screen button).
    public var isPageFullscreen: Bool { pages.fullscreenPageID != nil && pages.fullscreenPageID == state.selectedTabID }

    /// The selected page is full screen in this window (Chromium): the window fills the screen with the page alone.
    var isPageFullscreenInWindow: Bool { isPageFullscreen && fullscreenPage?.showsFullscreenInOwnWindow == false }

    /// The page showing HTML full screen, if it's the selected one.
    var fullscreenPage: (any WebPage)? { isPageFullscreen ? pages.fullscreenPageID.flatMap { pages.existingPage(for: $0) } : nil }

    #if os(macOS)
        /// The engine's own full-screen window showing the selected page (WebKit), if any.
        var engineFullscreenWindow: NSWindow? {
            guard let page = fullscreenPage, page.showsFullscreenInOwnWindow else { return nil }
            return page.view.window
        }
    #endif

    /// A page left showing full screen after another tab was chosen ends its full screen.
    func exitFullscreenOfUnselectedPage() {
        guard let id = pages.fullscreenPageID, id != state.selectedTabID else { return }
        pages.existingPage(for: id)?.exitFullscreen()
    }

    /// Leaves the selected page's full screen (the sidebar's "Exit Full Screen", Esc).
    public func exitPageFullscreen() {
        if let id = pages.fullscreenPageID { pages.existingPage(for: id)?.exitFullscreen() }
    }

    /// The scene id of browser windows (⌘N opens another).
    public static let browserWindowID = "browser"

    /// Another browser window (⌘N): the same library, pages, history, icons, extensions and Safe Browsing as
    /// `main`, with its own Space and tab, sidebar, command bar and Peek. It opens on `main`'s Space with no tab
    /// selected and the command bar ready.
    public static func window(sharing main: AppModel) -> AppModel {
        // From now on every window, including the first, keeps its own selection.
        if main.selection == nil {
            main.selection = WindowSelection(spaceID: main.store.state.selectedSpaceID, tabID: main.store.state.selectedTabID)
        }
        let window = AppModel(sharing: main)
        main.windowModels.removeAll { $0.model == nil }
        main.windowModels.append(WindowModelRef(model: window))
        window.selection = WindowSelection(spaceID: main.state.selectedSpaceID, tabID: nil)
        window.isSidebarVisible = main.isSidebarVisible
        return window
    }

    /// The window closed: its tabs no longer count as on screen.
    public func windowClosed() {
        pages.setShownTabs([], by: ObjectIdentifier(self))
        isCommandBarPresented = false
    }
}

#if canImport(SwiftUI)
    public import SwiftUI

    /// What a new browser window opens with. Each request is new (SwiftUI reuses a window opened with an equal
    /// value): ⌘N twice makes two windows.
    public struct BrowserWindowRequest: Codable, Hashable, Sendable {
        /// Distinguishes requests.
        public var id = UUID()
        /// A blank window (⌃⌘N): no tab selected, no command bar.
        public var blank: Bool
        /// A window open when Nera last quit, coming back.
        public var restoring: SavedWindow?

        /// A request.
        public init(blank: Bool) { self.blank = blank }

        /// A window coming back at launch.
        public init(restoring window: SavedWindow) {
            blank = false
            restoring = window
        }
    }

    /// A further browser window (⌘N): its own window model sharing the app's model, opened with the command bar.
    /// A blank one (⌃⌘N) opens on its start page instead. The first browser window shows the app's model itself.
    public struct BrowserWindowRoot: View {
        @State private var model: AppModel
        let request: BrowserWindowRequest?

        /// Creates a window sharing `main`, for `request` (nil: a new window with the command bar).
        public init(main: AppModel, request: BrowserWindowRequest?) {
            let model = AppModel.window(sharing: main)
            if let saved = request?.restoring {
                model.restore(saved)
                model.pendingFrame = saved.rect
            }
            _model = State(initialValue: model)
            self.request = request
        }

        /// The window.
        public var body: some View {
            RootView(model: model)
                #if os(macOS)
                    // A restored window goes back where it was; a new one opens just off the window in front.
                    .background(MatchFrontWindowFrame(offset: request?.restoring == nil ? CGSize(width: 26, height: -26) : nil))
                #endif
                .onAppear {
                    if request?.restoring != nil { return }
                    if request?.blank == true { model.send(.tab(.clearSelection)) } else { model.showCommandBar(.newTab) }
                }
                .onDisappear { model.windowClosed() }
        }
    }
#endif
