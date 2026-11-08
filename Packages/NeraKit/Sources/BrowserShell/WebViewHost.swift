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
            attach(page.view, to: container)
            return container
        }

        func updateNSView(_ container: PageContainerView, context: Context) {
            if container.subviews.first !== page.view { attach(page.view, to: container) }
            container.exposesPage = isAccessible
        }
    }

    /// Container whose accessibility children can be withheld while a modal prompt is up.
    final class PageContainerView: NSView {
        var exposesPage = true {
            didSet {
                guard exposesPage != oldValue else { return }
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
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
