// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import EngineKit
import Foundation
public import PageLifecycle
import SecurityPolicy

#if os(macOS)
    import AppKit
#endif

// Find in page and zoom.
extension AppModel {
    /// Chrome's zoom steps.
    public static let zoomSteps: [Double] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

    /// The next zoom step from `current` in `direction` (+1 in, -1 out).
    public static func nextZoom(from current: Double, direction: Int) -> Double {
        if direction > 0 { return zoomSteps.first { $0 > current + 0.001 } ?? zoomSteps.last ?? current }
        return zoomSteps.last { $0 < current - 0.001 } ?? zoomSteps.first ?? current
    }

    /// ⌘+ / ⌘−: zooms the current page one step and remembers it for the site in this profile.
    public func zoom(_ direction: Int) {
        guard let page = selectedPage else { return }
        setZoom(direction == 0 ? 1 : Self.nextZoom(from: page.state.zoom, direction: direction), on: page)
    }

    private func setZoom(_ factor: Double, on page: any WebPage) {
        page.setZoom(factor)
        if let profile = state.currentProfile, let host = state.selectedTab?.url?.host()?.lowercased() {
            send(.library(.setSiteZoom(profileID: profile.id, host: host, factor: factor)))
        }
        zoomIndicator = factor
        zoomIndicatorTask?.cancel()
        zoomIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { self?.zoomIndicator = nil }
        }
    }

    /// ⌘F: shows the find bar (keeps the last query, like Chrome).
    public func showFindBar() {
        guard selectedPage != nil else { return }
        isFindBarPresented = true
    }

    /// Esc / Done: hides the find bar and removes highlighting.
    public func hideFindBar() {
        isFindBarPresented = false
        findResult = nil
        selectedPage?.clearFindResults()
    }

    /// Finds `findQuery`: the first match after typing, then the next/previous match (⌘G / ⇧⌘G).
    public func find(backwards: Bool = false) async {
        guard let page = selectedPage else { return }
        let query = findQuery
        guard !query.isEmpty else {
            page.clearFindResults()
            findResult = nil
            return
        }
        let result = await page.find(query, options: FindOptions(backwards: backwards))
        if query == findQuery { findResult = result }
    }

    // MARK: Developer tools

    /// Turns developer tools on or off for every page (SEC-056).
    public func setDeveloperTools(_ on: Bool) {
        send(.library(.setDeveloperTools(on)))
        pages.devToolsEnabled = on
    }

    /// ⌥⌘I: opens DevTools for the current page, asking first while they're turned off.
    public func showDevTools() {
        guard state.settings.isDeveloperToolsEnabled else {
            isConfirmingDevTools = true
            return
        }
        guard let page = selectedPage else { return }
        if !page.showDevTools() {
            notice = "Right-click the page and choose Inspect Element to open the Web Inspector."
        }
    }

    // MARK: Split View

    /// Split View: every tab of the selected tab's split with its live page, in display order. Empty when the
    /// selected tab isn't in a split. Keeps all panes loaded (they're on screen).
    public var splitPanes: [(tab: BrowserCore.Tab, page: any WebPage)] {
        guard let split = state.selectedSplit, let profile = state.currentProfile, let selected = state.selectedTabID else {
            pages.visibleTabIDs = []
            return []
        }
        pages.visibleTabIDs = Set(split.tabs.map(\.id))
        // The selected pane last, so it stays the active page.
        let ordered = split.tabs.filter { $0.id != selected } + split.tabs.filter { $0.id == selected }
        let live = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, pages.page(for: $0, profile: profile)) })
        return split.tabs.compactMap { tab in live[tab.id].map { (tab, $0) } }
    }

    // MARK: Downloads

    /// Shows a finished download in Finder (selects it; never opens it, SEC-044).
    public func revealDownload(_ item: DownloadItem) {
        #if os(macOS)
            guard let file = item.fileURL, FileManager.default.fileExists(atPath: file.path) else {
                notice = "\(item.filename) was moved or deleted."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        #endif
    }
}
