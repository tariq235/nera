// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import SwiftUI

    /// While a page is full screen in the engine's own window (WebKit), the sidebar slides in over that window's
    /// left edge, the same as over Nera's own full screen: a borderless panel attached to the window holds the
    /// same peeking sidebar. While the sidebar is away the panel is a thin strip at the edge, so the video
    /// underneath gets every other click.
    struct EngineFullscreenSidebar: NSViewRepresentable {
        let model: AppModel
        /// The engine's full-screen window, or nil when none is showing the selected page.
        let window: NSWindow?
        let isPeeking: Bool
        let width: CGFloat

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.update(window: window, model: model, isPeeking: isPeeking, width: width)
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }

        func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor final class Coordinator {
            private var panel: NSPanel?
            private weak var host: NSWindow?
            private var resizeObserver: (any NSObjectProtocol)?
            private var isPeeking = false
            private var width: CGFloat = 0
            /// Shrinking back to the strip waits for the sidebar's slide out to finish.
            private var shrink: DispatchWorkItem?

            func update(window: NSWindow?, model: AppModel, isPeeking: Bool, width: CGFloat) {
                if window !== host {
                    detach()
                    if let window { attach(to: window, model: model, width: width) }
                }
                self.isPeeking = isPeeking
                self.width = width
                shrink?.cancel()
                if isPeeking {
                    layout()
                } else {
                    let work = DispatchWorkItem { [weak self] in self?.layout() }
                    shrink = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
                }
            }

            private func attach(to window: NSWindow, model: AppModel, width: CGFloat) {
                let panel = NSPanel(
                    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = false  // the clear strip at the edge still takes the pointer
                panel.becomesKeyOnlyIfNeeded = true
                panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
                panel.contentView = NSHostingView(
                    rootView: PeekingSidebar(model: model, width: width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.isSidebarPeeking)
                        .preferredColorScheme(model.preferredColorScheme))
                host = window
                self.panel = panel
                self.width = width
                layout()
                window.addChildWindow(panel, ordered: .above)
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
            }

            func detach() {
                shrink?.cancel()
                if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
                resizeObserver = nil
                if let panel {
                    panel.parent?.removeChildWindow(panel)
                    panel.orderOut(nil)
                }
                panel = nil
                host = nil
            }

            /// The panel runs down the window's left edge: the sidebar's width while it's in, a strip otherwise.
            private func layout() {
                guard let panel, let host else { return }
                let frame = host.frame
                let panelWidth = isPeeking ? width + 40 : 6
                panel.setFrame(NSRect(x: frame.minX, y: frame.minY, width: panelWidth, height: frame.height), display: true)
            }
        }
    }
#endif
