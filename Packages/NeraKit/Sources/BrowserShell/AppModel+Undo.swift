// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import BrowserCore

    /// ⌘Z, like Arc: text being edited undoes as usual; with nothing being edited, what was closed last comes back.
    extension AppModel {
        /// Whether the page has a text field (or editable area, or a frame, which may hold one) in focus.
        static let pageEditingScript = """
            (() => { const e = document.activeElement;
              return e && (e.isContentEditable || /^(INPUT|TEXTAREA|SELECT|IFRAME)$/.test(e.tagName)) ? 'yes' : 'no' })()
            """

        /// Edit › Undo (⌘Z).
        public func undo() {
            let responder = NSApp.keyWindow?.firstResponder
            // A text field or text view of Nera's (the command bar, a rename, Settings): its own undo.
            if responder is NSTextView { return sendUndoToResponder() }
            // The page has the keyboard: a focused field in it undoes; otherwise the closed tab comes back.
            if let view = responder as? NSView, let page = selectedPage, view === page.view || view.isDescendant(of: page.view) {
                Task { @MainActor in
                    if await page.evaluate(Self.pageEditingScript) == "yes" { sendUndoToResponder() } else { send(.tab(.undoClose)) }
                }
                return
            }
            send(.tab(.undoClose))
        }

        private func sendUndoToResponder() { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
    }
#endif
