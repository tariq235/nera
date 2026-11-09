// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import Foundation

    extension DemoMode {
        /// The selected page view's size, its holder and its window's size: where full screen put it.
        @MainActor static func pageGeometry(_ model: AppModel) -> String {
            guard let id = model.state.selectedTabID, let view = model.pages.existingPage(for: id)?.view else { return "-" }
            let size = { (r: NSRect) in "\(Int(r.width))x\(Int(r.height))" }
            let holder = view.superview.map { String(describing: type(of: $0)) } ?? "none"
            return "\(size(view.frame))@\(Int(view.frame.minY)) in \(holder) win \(view.window.map { size($0.frame) } ?? "none")"
        }

        /// `--trace`: prints the window state whenever it changes (command bar, Space, tab, tab count, windows), for
        /// scripts that drive Nera with real key and mouse events and check what happened.
        static func traceIfRequested(_ model: AppModel) {
            guard CommandLine.arguments.contains("--trace") else { return }
            Task { @MainActor in
                var last = ""
                while true {
                    let state = model.state
                    let tabs = state.spaces.flatMap { state.orderedTabs(in: $0) }.count
                    let windows = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count
                    let line =
                        "trace: bar=\(model.isCommandBarPresented ? 1 : 0) space=\(state.selectedSpace?.title ?? "-") "
                        + "tab=\(state.selectedTab?.displayTitle ?? "-") tabs=\(tabs) windows=\(windows) sidebar=\(model.isSidebarVisible ? 1 : 0) fullscreen=\(model.pages.fullscreenPageID == nil ? 0 : 1) peek=\(model.isSidebarPeeking ? 1 : 0)"
                        + " page=\(pageGeometry(model))"
                    if line != last {
                        FileHandle.standardOutput.write(Data((line + "\n").utf8))  // Debug tool output
                        last = line
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }
#endif
