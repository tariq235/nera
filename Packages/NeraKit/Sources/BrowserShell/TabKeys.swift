// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import SwiftUI

    /// The other usual ways to move between tabs, besides ⇧⌘] / ⇧⌘[ in the menu: ⌥⌘↓ / ⌥⌘↑ and ⌃Tab / ⌃⇧Tab.
    /// Only in the window it's in.
    struct TabKeys: NSViewRepresentable {
        let model: AppModel

        func makeNSView(context: Context) -> Watcher {
            let view = Watcher()
            view.model = model
            return view
        }

        func updateNSView(_ view: Watcher, context: Context) { view.model = model }

        final class Watcher: NSView {
            weak var model: AppModel?
            private var monitor: Any?

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, event.window === self.window, let model = self.model, let offset = Self.offset(for: event)
                    else { return event }
                    model.send(.tab(.selectAdjacent(offset: offset)))
                    return nil
                }
            }

            /// ±1 for the tab keys, nil for anything else.
            static func offset(for event: NSEvent) -> Int? {
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                switch (event.keyCode, mods) {
                case (125, [.command, .option]): return 1  // ↓
                case (126, [.command, .option]): return -1  // ↑
                case (48, [.control]): return 1  // Tab
                case (48, [.control, .shift]): return -1
                default: return nil
                }
            }

            override func removeFromSuperview() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                super.removeFromSuperview()
            }
        }
    }
#endif
