// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import Foundation

#if os(macOS)
    import AppKit
#endif

/// A browser window as it was when Nera quit: its Space and tab, and where it was on screen.
public struct SavedWindow: Codable, Hashable, Sendable {
    /// The window's Space.
    public var spaceID: UUID
    /// Its tab; nil: its start page.
    public var tabID: UUID?
    /// Its frame on screen (x, y, width, height); nil: placed like a new window.
    public var frame: [Double]?

    /// A saved window.
    public init(spaceID: UUID, tabID: UUID?, frame: CGRect?) {
        self.spaceID = spaceID
        self.tabID = tabID
        self.frame = frame.map { [$0.minX, $0.minY, $0.width, $0.height] }
    }

    /// Its frame on screen.
    var rect: CGRect? {
        guard let frame, frame.count == 4 else { return nil }
        return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
    }
}

/// The browser windows open when Nera quits come back when it opens again, each on its Space and tab, as in Arc.
/// macOS's own window restoration stays off (NeraApp): it could bring Nera back with no window at all. Private
/// windows and Little Windows never come back.
public enum WindowRestore {
    /// Where the windows are kept between launches.
    static let key = "NeraBrowserWindows"

    /// UI tests start from no windows, except the one about this.
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["NERA_UI_TEST"] == nil || environment["NERA_RESTORE_WINDOWS"] != nil
    }

    /// Keeps `windows` (front to back) for the next launch.
    static func save(_ windows: [SavedWindow], in defaults: UserDefaults = .standard) {
        guard isEnabled else { return }
        if windows.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(windows) {
            defaults.set(data, forKey: key)
        }
    }

    /// The windows kept at the last quit, once: taking them forgets them, so a crash never opens them twice.
    static func take(from defaults: UserDefaults = .standard) -> [SavedWindow] {
        guard isEnabled, let data = defaults.data(forKey: key) else { return [] }
        defaults.removeObject(forKey: key)
        return (try? JSONDecoder().decode([SavedWindow].self, from: data)) ?? []
    }
}

/// A further browser window's model, held weakly by the first window's (the window owns it).
struct WindowModelRef {
    weak var model: AppModel?
}

extension AppModel {
    /// This window as it is now, if it's open (on screen or in the Dock).
    var savedWindow: SavedWindow? {
        #if os(macOS)
            guard let window = hostWindow, window.isVisible || window.isMiniaturized else { return nil }
            return SavedWindow(spaceID: state.selectedSpaceID, tabID: state.selectedTabID, frame: window.frame)
        #else
            return nil
        #endif
    }

    /// Nera is quitting: keeps its browser windows, front to back, for the next launch.
    public func saveWindowsForRelaunch(in defaults: UserDefaults = .standard) {
        #if os(macOS)
            let models = [self] + windowModels.compactMap(\.model)
            let order = NSApp.orderedWindows
            let saved = models.compactMap { model -> (Int, SavedWindow)? in
                guard let window = model.hostWindow, let saved = model.savedWindow else { return nil }
                return (order.firstIndex { $0 === window } ?? order.count, saved)
            }
            WindowRestore.save(saved.sorted { $0.0 < $1.0 }.map(\.1), in: defaults)
        #endif
    }

    /// Nera opened: the first window takes the front window kept at the last quit, and the others open again
    /// behind it. `open` opens a browser window for a request. Nothing comes back in safe mode.
    public func restoreWindows(from defaults: UserDefaults = .standard, open: (BrowserWindowRequest) -> Void) {
        let saved = WindowRestore.take(from: defaults)
        guard !isSafeMode, let front = saved.first else { return }
        store.restoreSelection(spaceID: front.spaceID, tabID: front.tabID)
        #if os(macOS)
            // After SwiftUI has put the window where it was last (it does so as the window appears).
            if let frame = front.rect, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                DispatchQueue.main.async { [weak self] in self?.hostWindow?.setFrame(frame, display: true) }
            }
        #endif
        guard saved.count > 1 else { return }
        // Opened back to front; then this window comes back in front of them, as it was.
        for window in saved.dropFirst().reversed() {
            open(BrowserWindowRequest(restoring: window))
        }
        #if os(macOS)
            DispatchQueue.main.async { [weak self] in self?.hostWindow?.makeKeyAndOrderFront(nil) }
        #endif
    }

    /// Puts a restored window on its Space and tab (if they still exist; else the first window's Space).
    func restore(_ saved: SavedWindow) {
        let space = store.state.spaces.contains { $0.id == saved.spaceID } ? saved.spaceID : store.state.selectedSpaceID
        let tab = saved.tabID.flatMap { store.state.locate($0) == nil ? nil : $0 }
        selection = WindowSelection(spaceID: space, tabID: space == saved.spaceID ? tab : nil)
    }
}

#if os(macOS)
    public import SwiftUI

    extension View {
        /// The first browser window: once it's shown, the windows open at the last quit come back.
        public func restoringWindows(_ model: AppModel) -> some View { modifier(RestoreWindows(model: model)) }
    }

    private struct RestoreWindows: ViewModifier {
        let model: AppModel
        @Environment(\.openWindow) private var openWindow
        @State private var isDone = false

        func body(content: Content) -> some View {
            content.onAppear {
                guard !isDone else { return }
                isDone = true
                model.restoreWindows { openWindow(id: AppModel.browserWindowID, value: $0) }
            }
        }
    }
#endif
