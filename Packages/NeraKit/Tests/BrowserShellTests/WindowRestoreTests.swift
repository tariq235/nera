// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import BrowserCore
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// The browser windows open at quit come back at the next launch, each on its Space and tab.
@MainActor
struct WindowRestoreTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "WindowRestoreTests-\(UUID().uuidString)"))
    }

    /// A model with two Spaces and a tab in each.
    struct Library {
        let model: AppModel
        let spaces: [UUID]
        let tabs: [UUID]
    }

    func library() throws -> Library {
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))
        m.send(.tab(.open(URL(string: "https://a.example")!, .newTab)))
        let first = (m.state.selectedSpaceID, try #require(m.state.selectedTabID))
        m.send(.space(.create(title: "Work")))
        m.send(.tab(.open(URL(string: "https://b.example")!, .newTab)))
        let second = (m.state.selectedSpaceID, try #require(m.state.selectedTabID))
        #expect(first.0 != second.0)
        return Library(model: m, spaces: [first.0, second.0], tabs: [first.1, second.1])
    }

    func window(_ frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: false)
        window.orderFront(nil)
        return window
    }

    @Test func savedWindowsAreTakenOnce() {
        let saved = [SavedWindow(spaceID: UUID(), tabID: nil, frame: CGRect(x: 10, y: 20, width: 900, height: 600))]
        WindowRestore.save(saved, in: defaults)
        #expect(WindowRestore.take(from: defaults) == saved)
        #expect(WindowRestore.take(from: defaults).isEmpty, "a crash right after launch doesn't open them twice")
        #expect(saved[0].rect == CGRect(x: 10, y: 20, width: 900, height: 600))
    }

    @Test func quittingKeepsEveryBrowserWindowFrontToBack() throws {
        let library = try library()
        let (m, spaces, tabs) = (library.model, library.spaces, library.tabs)
        let other = AppModel.window(sharing: m)
        other.restore(SavedWindow(spaceID: spaces[0], tabID: tabs[0], frame: nil))
        let back = window(CGRect(x: 100, y: 100, width: 1000, height: 700))
        let front = window(CGRect(x: 160, y: 80, width: 1100, height: 750))
        m.hostWindow = back
        other.hostWindow = front
        front.orderFront(nil)
        defer {
            back.close()
            front.close()
        }
        m.saveWindowsForRelaunch(in: defaults)
        let saved = WindowRestore.take(from: defaults)
        #expect(saved.map(\.spaceID) == [spaces[0], spaces[1]], "front window first")
        #expect(saved.map(\.tabID) == [tabs[0], tabs[1]])
        #expect(saved.first?.rect == front.frame)
        back.orderOut(nil)
        m.saveWindowsForRelaunch(in: defaults)
        #expect(WindowRestore.take(from: defaults).count == 1, "closed windows don't come back")
    }

    @Test func launchingBringsTheWindowsBack() throws {
        let library = try library()
        let (m, spaces, tabs) = (library.model, library.spaces, library.tabs)
        let front = SavedWindow(spaceID: spaces[0], tabID: tabs[0], frame: nil)
        let behind = SavedWindow(spaceID: spaces[1], tabID: tabs[1], frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let gone = SavedWindow(spaceID: UUID(), tabID: UUID(), frame: nil)
        WindowRestore.save([front, behind, gone], in: defaults)
        var opened: [BrowserWindowRequest] = []
        m.restoreWindows(from: defaults) { opened.append($0) }
        #expect(m.state.selectedSpaceID == spaces[0] && m.state.selectedTabID == tabs[0], "the first window takes the front one")
        #expect(opened.map(\.restoring) == [gone, behind], "the others open back to front")
        let restored = AppModel.window(sharing: m)
        restored.restore(behind)
        #expect(restored.state.selectedSpaceID == spaces[1] && restored.state.selectedTabID == tabs[1])
        let fallback = AppModel.window(sharing: m)
        fallback.restore(gone)
        #expect(
            fallback.state.selectedSpaceID == m.state.selectedSpaceID && fallback.state.selectedTabID == nil,
            "a window whose Space is gone opens on the first window's Space")
    }

    @Test func safeModeBringsNothingBack() throws {
        let library = try library()
        let (m, spaces) = (library.model, library.spaces)
        WindowRestore.save(
            [SavedWindow(spaceID: spaces[0], tabID: nil, frame: nil)] + [SavedWindow(spaceID: spaces[1], tabID: nil, frame: nil)],
            in: defaults)
        m.enterSafeMode()
        var opened = 0
        m.restoreWindows(from: defaults) { _ in opened += 1 }
        #expect(opened == 0)
    }

    @Test func aTabDraggedOutOpensInAWindowOfItsOwn() throws {
        let library = try library()
        let m = library.model
        m.send(.tab(.select(library.tabs[1])))
        m.send(.tab(.open(URL(string: "https://c.example")!, .newTab)))
        let dragged = try #require(m.state.selectedTabID)
        m.openInNewWindow(dragged, at: CGPoint(x: 300, y: 900))
        let request = try #require(m.pendingBrowserWindow?.restoring)
        #expect(request.tabID == dragged && request.spaceID == library.spaces[1])
        #expect(request.rect?.minX == 300 && request.rect?.maxY == 900, "its top-left corner where it was dropped")
        #expect(m.state.selectedTabID == library.tabs[1], "this window goes back to the tab used before")
        m.openInNewWindow(UUID(), at: .zero)
        #expect(m.pendingBrowserWindow?.restoring?.tabID == dragged, "an unknown tab opens nothing")
    }
}
