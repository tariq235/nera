// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import SwiftUI
#endif

#if os(macOS)
    /// A private window opens at once (no zoom-in), dark from its first frame (no white flash), with exactly the
    /// size and place of the browser window behind it: it's a full browser window, not a small one.
    struct MatchMainWindowFrame: View {
        var body: some View { MatchFrontWindowFrame(offset: .zero, isDark: true) }
    }

    /// Opens a window at once with the size of the browser window in front, moved by `offset` (nil: leave the
    /// window where it is). It stays invisible until it's in place, so it never appears somewhere else first.
    struct MatchFrontWindowFrame: NSViewRepresentable {
        var offset: CGSize?
        var isDark = false

        func makeNSView(context: Context) -> NSView {
            let view = Matcher()
            view.offset = offset
            view.isDark = isDark
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}

        final class Matcher: NSView {
            var offset: CGSize?
            var isDark = false
            private var placed = false

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window, let offset, !placed else { return }
                placed = true
                window.animationBehavior = .none
                if isDark {
                    window.appearance = NSAppearance(named: .darkAqua)
                    window.backgroundColor = NSColor(white: 0.13, alpha: 1)
                }
                guard
                    let front = NSApp.orderedWindows.first(where: {
                        $0 !== window && $0.isVisible && $0.canBecomeMain && $0.frame.width >= 820
                    })
                else { return }
                let frame = front.frame.offsetBy(dx: offset.width, dy: offset.height)
                window.setFrame(frame, display: false)
                // AppKit staggers new windows when it shows them: keep it invisible until it's in place.
                window.alphaValue = 0
                DispatchQueue.main.async {
                    window.setFrame(frame, display: true)
                    window.alphaValue = 1
                }
            }
        }
    }
#endif

#if os(macOS)
    /// Puts the window in macOS full screen while a page shows HTML full screen, and back afterwards (only if it put
    /// it there: a window that was already full screen stays so). Leaving full screen another way (the green button,
    /// Mission Control) ends the page's full screen too, through `exitPage`.
    struct FullScreenWindow: NSViewRepresentable {
        let isOn: Bool
        let exitPage: () -> Void

        func makeNSView(context: Context) -> Controller { Controller() }

        func updateNSView(_ view: Controller, context: Context) {
            view.exitPage = exitPage
            view.set(isOn)
        }

        final class Controller: NSView {
            var exitPage: () -> Void = {}
            private var isOn = false
            private var enteredForPage = false
            private var exitObserver: (any NSObjectProtocol)?
            private var escMonitor: Any?

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let exitObserver { NotificationCenter.default.removeObserver(exitObserver) }
                exitObserver = nil
                guard let window else { return }
                exitObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.enteredForPage = false
                        if self.isOn { self.exitPage() }  // the window left full screen first: end the page's too
                    }
                }
            }

            func set(_ on: Bool) {
                guard on != isOn, let window else { return }
                isOn = on
                // Esc leaves a page's full screen (Chrome does this in its own window code, which Nera replaces).
                if let escMonitor { NSEvent.removeMonitor(escMonitor) }
                escMonitor = nil
                if on {
                    escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                        guard let self, event.keyCode == 53, event.window === self.window else { return event }
                        self.exitPage()
                        return nil
                    }
                }
                let isFullScreen = window.styleMask.contains(.fullScreen)
                if on, !isFullScreen {
                    enteredForPage = true
                    window.toggleFullScreen(nil)
                } else if !on, enteredForPage, isFullScreen {
                    enteredForPage = false
                    window.toggleFullScreen(nil)
                }
            }
        }
    }
#endif
