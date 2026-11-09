// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
public import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Menu bar commands and default shortcuts (macOS menu bar, iPad hardware keyboard).
/// Defaults follow widely used shortcuts, so switching from another browser is painless.
public struct BrowserCommands: Commands {
    let mainModel: AppModel
    /// The model of the focused window (a private window has its own); the main window's otherwise.
    @FocusedValue(\.neraModel) private var focusedModel: AppModel?
    @Environment(\.openWindow) private var openWindow

    private var model: AppModel { focusedModel ?? mainModel }

    /// Creates the menu commands; `model` is the main window's model.
    public init(model: AppModel) {
        self.mainModel = model
    }

    /// The menus.
    public var body: some Commands {
        CommandGroup(after: .appSettings) {
            #if os(macOS)
                Button("Set as Default Browser") { DefaultBrowser.makeDefault { _ in } }
                    .disabled(DefaultBrowser.isDefault)
            #endif
            Button("Clear Browsing Data…") { model.isClearDataPresented = true }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.isPrivate)
            Divider()
            Button("Import from Arc…") { model.requestArcImport() }  // naming: import-reference
            #if os(macOS)
                Button("Import from Another Browser…") { model.isBrowserImportPresented = true }
            #endif
            Button("Check for Updates…") { model.checkForUpdates(force: true) }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab…") { model.showCommandBar(.newTab) }.keyboardShortcut("t")
            Button("New Window") { openWindow(id: AppModel.browserWindowID) }.keyboardShortcut("n")
            Button("Open Location…") { model.showCommandBar(.currentTab) }.keyboardShortcut("l")
            Button("New Private Window") { openWindow(id: AppModel.privateWindowID) }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Tab in Split View…") { model.showCommandBar(.splitWithCurrent) }.keyboardShortcut(
                "n", modifiers: [.command, .control]
            )
            .disabled(model.state.selectedTab == nil)
            Button("Restore Last Closed Tab") { model.send(.tab(.restoreLastClosed)) }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            // ⌘W closes what's in front: the command bar if it's open, otherwise the tab. Only an empty private
            // window closes itself; the main window never closes on ⌘W (⇧⌘W closes it).
            Button("Close Tab") { model.closeFrontmost() }
                .keyboardShortcut("w")
            #if os(macOS)
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w", modifiers: [.command, .shift])
            #endif
        }
        CommandMenu("Tabs") {
            Button("Pin / Unpin Tab") { model.togglePinSelectedTab() }.keyboardShortcut("d")
            Button("Next Tab") { model.send(.tab(.selectAdjacent(offset: 1))) }.keyboardShortcut(
                .downArrow, modifiers: [.command, .option])
            Button("Previous Tab") { model.send(.tab(.selectAdjacent(offset: -1))) }.keyboardShortcut(
                .upArrow, modifiers: [.command, .option])
            Button("Clear Today Tabs") { model.send(.space(.clearToday)) }.keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("History") { model.isHistoryPresented = true }.keyboardShortcut("y").disabled(model.isPrivate)
            Button(model.currentPageBookmark == nil ? "Bookmark This Page" : "Remove Bookmark") { model.toggleBookmarkForCurrentPage() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.state.selectedTab?.url == nil || model.isPrivate)
            Button("Bookmark Manager") { model.isBookmarksPresented = true }.keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(model.isPrivate)
            Button("Downloads") { model.isDownloadsTrayPresented.toggle() }.keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(model.pages.downloads.isEmpty)
            Button("Style This Site…") { model.isSiteStyleEditorPresented.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .control])
                .disabled(model.isPrivate || SiteStyle.site(of: model.state.selectedTab?.url) == nil)
            Button("Find…") { model.showFindBar() }.keyboardShortcut("f")
            Button("Find Next") { Task { await model.find() } }.keyboardShortcut("g").disabled(model.findQuery.isEmpty)
            Button("Find Previous") { Task { await model.find(backwards: true) } }.keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model.findQuery.isEmpty)
            Button("Copy URL") { Clipboard.copy(model.currentURLString) }.keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            ForEach(1...9, id: \.self) { number in
                let tab = model.shortcutTab(number)
                Button(tab.map { "\(number == 9 ? "Last" : "\(number).") \($0.displayTitle)" } ?? "Favorite \(number)") {
                    model.selectShortcutTab(number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(tab == nil)
            }
        }
        CommandMenu("Spaces") {
            Button("Next Space") { model.send(.space(.selectAdjacent(offset: 1))) }.keyboardShortcut(
                .rightArrow, modifiers: [.command, .option])
            Button("Previous Space") { model.send(.space(.selectAdjacent(offset: -1))) }.keyboardShortcut(
                .leftArrow, modifiers: [.command, .option])
            Divider()
            ForEach(Array(model.state.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button(space.title) { model.send(.space(.select(space.id))) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control])
            }
        }
        CommandGroup(after: .toolbar) {
            Button(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") { model.isSidebarVisible.toggle() }.keyboardShortcut("s")
            Divider()
            Button("Reload Page") { model.reload() }.keyboardShortcut("r")
            Button("Actual Size") { model.zoom(0) }.keyboardShortcut("0")
            Button("Zoom In") { model.zoom(1) }.keyboardShortcut("=")
            Button("Zoom Out") { model.zoom(-1) }.keyboardShortcut("-")
            Divider()
            Button("Developer Tools") { model.showDevTools() }.keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model.state.selectedTab == nil)
            Button("Back") { model.goBack() }.keyboardShortcut("[")
            Button("Forward") { model.goForward() }.keyboardShortcut("]")
        }
    }
}

/// Lets menu commands find the focused window's model.
public struct NeraModelKey: FocusedValueKey {
    /// The model.
    public typealias Value = AppModel
}

extension FocusedValues {
    /// The focused window's app model.
    public var neraModel: AppModel? {
        get { self[NeraModelKey.self] }
        set { self[NeraModelKey.self] = newValue }
    }
}
