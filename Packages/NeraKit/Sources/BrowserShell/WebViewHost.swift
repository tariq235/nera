// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import SwiftUI

/// Hosts an engine's native view. The container stays put; the page view is swapped in.
/// Works for any engine because it only knows ``PlatformView``.
///
/// `isAccessible` is `false` while a page prompt (dialog, permission…) is shown on top. The page
/// underneath is then removed from the accessibility tree, like content behind any modal dialog.
/// This also matters for correctness: during `alert()`/`confirm()` the engine's content process is
/// blocked waiting for the answer, so assistive technologies walking into the page would hang.
#if os(macOS)
    struct WebViewHost: NSViewRepresentable {
        let page: any WebPage
        var isAccessible = true

        func makeNSView(context: Context) -> PageContainerView {
            let container = PageContainerView()
            container.page = page.view
            return container
        }

        func updateNSView(_ container: PageContainerView, context: Context) {
            container.page = page.view
            container.exposesPage = isAccessible
        }
    }

    /// Holds a page's view. Several browser windows can select the same tab, but a view lives in one window: the
    /// window being used shows it, the others say where it is until they're used (ADR-0013).
    final class PageContainerView: NSView {
        var page: NSView? {
            didSet { if page !== oldValue { showPageIfFree() } }
        }
        private let elsewhere = NSTextField(labelWithString: "Showing in another window")

        var exposesPage = true {
            didSet {
                guard exposesPage != oldValue else { return }
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }

        private var keyObserver: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            guard let window else { return }
            // This window is now the one in use: show the page here if another window had it.
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.showPageIfFree(force: true) }
            }
            showPageIfFree()
        }

        override func willRemoveSubview(_ subview: NSView) {
            super.willRemoveSubview(subview)
            // Another window took the page: say where it went. Only while this view is on screen: a view being
            // freed also removes its subviews, and must not be referenced then.
            guard subview === page, window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.showPageIfFree() }
        }

        /// Shows the page here unless another window that's in use shows it; `force`: this window is now in use.
        private func showPageIfFree(force: Bool = false) {
            guard let page, window != nil else { return }
            if page.superview === self { return elsewhere.removeFromSuperview() }
            let shownElsewhere = page.window != nil && page.window !== window
            if shownElsewhere && !force && page.window?.isKeyWindow == true {
                if elsewhere.superview == nil {
                    elsewhere.textColor = .secondaryLabelColor
                    elsewhere.translatesAutoresizingMaskIntoConstraints = false
                    addSubview(elsewhere)
                    NSLayoutConstraint.activate([
                        elsewhere.centerXAnchor.constraint(equalTo: centerXAnchor),
                        elsewhere.centerYAnchor.constraint(equalTo: centerYAnchor),
                    ])
                }
                return
            }
            elsewhere.removeFromSuperview()
            attach(page, to: self)
        }

        override func accessibilityChildren() -> [Any]? {
            exposesPage ? super.accessibilityChildren() : []
        }
    }
#else
    struct WebViewHost: UIViewRepresentable {
        let page: any WebPage
        var isAccessible = true

        func makeUIView(context: Context) -> UIView {
            let container = UIView()
            attach(page.view, to: container)
            return container
        }

        func updateUIView(_ container: UIView, context: Context) {
            if container.subviews.first !== page.view { attach(page.view, to: container) }
            container.accessibilityElementsHidden = !isAccessible
        }
    }
#endif

@MainActor
private func attach(_ view: PlatformView, to container: PlatformView) {
    for subview in container.subviews { subview.removeFromSuperview() }
    view.removeFromSuperview()
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        view.topAnchor.constraint(equalTo: container.topAnchor),
        view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
}
