// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import Foundation

    extension DemoMode {
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
                        + "tab=\(state.selectedTab?.displayTitle ?? "-") tabs=\(tabs) windows=\(windows) sidebar=\(model.isSidebarVisible ? 1 : 0) fullscreen=\(model.pages.fullscreenPageID == nil ? 0 : 1)"
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
