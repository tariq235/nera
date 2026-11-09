// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import Foundation
import Observation

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
        guard let selection else { return store.send(action) }
        // Several windows share the library: act on this window's Space and tab, then keep where it lands.
        store.restoreSelection(spaceID: selection.spaceID, tabID: selection.tabID)
        store.send(action)
        self.selection = WindowSelection(spaceID: store.state.selectedSpaceID, tabID: store.state.selectedTabID)
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

    /// A further browser window (⌘N): its own window model sharing the app's model, opened with the command bar.
    /// The first browser window shows the app's model itself.
    public struct BrowserWindowRoot: View {
        @State private var model: AppModel

        /// Creates a window sharing `main`.
        public init(main: AppModel) {
            _model = State(initialValue: AppModel.window(sharing: main))
        }

        /// The window.
        public var body: some View {
            RootView(model: model)
                #if os(macOS)
                    .background(MatchFrontWindowFrame(offset: CGSize(width: 26, height: -26)))
                #endif
                .onAppear { model.showCommandBar(.newTab) }
                .onDisappear { model.windowClosed() }
        }
    }
#endif
