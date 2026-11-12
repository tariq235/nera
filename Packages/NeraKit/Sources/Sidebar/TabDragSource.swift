// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import SwiftUI

    /// Over a tab's row: a click selects the tab; a drag carries it, to drop anywhere in the sidebar (its ID, as
    /// SwiftUI drags do) or, as in Arc, outside Nera's windows to open it in a window of its own. SwiftUI's own drag
    /// can't tell where a drop that nobody took ended, so the row starts the drag itself. It leaves the row's
    /// trailing `buttons` points (close, mute) and right clicks (the tab's menu) to SwiftUI.
    struct TabDragSource: NSViewRepresentable {
        let tabID: UUID
        let buttons: CGFloat
        let select: () -> Void
        let dropOutside: (CGPoint) -> Void

        func makeNSView(context: Context) -> Source { Source() }

        func updateNSView(_ view: Source, context: Context) {
            view.tabID = tabID
            view.buttons = buttons
            view.select = select
            view.dropOutside = dropOutside
        }

        final class Source: NSView, NSDraggingSource {
            var tabID = UUID()
            var buttons: CGFloat = 0
            var select: () -> Void = {}
            var dropOutside: (CGPoint) -> Void = { _ in }
            private var downAt: NSPoint?
            private var dragged = false

            // The tab's menu: right clicks (and ⌃-clicks) go on to the row's own handling.
            override func hitTest(_ point: NSPoint) -> NSView? {
                let event = NSApp.currentEvent
                if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true { return nil }
                guard let local = superview.map({ convert(point, from: $0) }), local.x < bounds.width - buttons else { return nil }
                return super.hitTest(point)
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func mouseDown(with event: NSEvent) {
                downAt = event.locationInWindow
                dragged = false
            }

            override func mouseDragged(with event: NSEvent) {
                guard !dragged, let downAt else { return }
                let moved = hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y)
                guard moved > 4 else { return }
                dragged = true
                let item = NSPasteboardItem()
                item.setString(tabID.uuidString, forType: .string)
                let dragging = NSDraggingItem(pasteboardWriter: item)
                dragging.setDraggingFrame(bounds, contents: snapshot())
                let session = beginDraggingSession(with: [dragging], event: event, source: self)
                session.animatesToStartingPositionsOnCancelOrFail = false
            }

            override func mouseUp(with event: NSEvent) {
                if !dragged, downAt != nil { select() }
                downAt = nil
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                context == .withinApplication ? .move : []
            }

            func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
                downAt = nil
                guard operation.isEmpty else { return }  // something in Nera took it
                let overNera = NSApp.windows.contains { $0.isVisible && $0.frame.contains(screenPoint) }
                if !overNera { dropOutside(screenPoint) }
            }

            /// The row as it looks now, to drag.
            private func snapshot() -> NSImage {
                guard let host = superview, let rep = host.bitmapImageRepForCachingDisplay(in: frame) else { return NSImage() }
                host.cacheDisplay(in: frame, to: rep)
                let image = NSImage(size: frame.size)
                image.addRepresentation(rep)
                return image
            }
        }
    }
#endif
