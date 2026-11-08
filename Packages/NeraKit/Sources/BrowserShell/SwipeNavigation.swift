// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import SwiftUI

#if os(macOS)
    import AppKit

    /// Passes an event through `MainActor.assumeIsolated` (monitors already run on the main thread).
    private struct EventBox: @unchecked Sendable {
        let event: NSEvent?
    }

    /// A view that never takes clicks (they reach the title bar area beneath it).
    final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    /// Two-finger trackpad swipes in a browser window: on the sidebar they move between Spaces (the Space
    /// follows the fingers); on the page they go back or forward (an arrow follows the fingers and fills
    /// when letting go would navigate). Only horizontal swipes count; vertical scrolling is untouched.
    struct SwipeNavigation: NSViewRepresentable {
        let model: AppModel
        /// The sidebar's width, when it's showing.
        let sidebarWidth: CGFloat?

        func makeNSView(context: Context) -> NSView {
            let view = PassThroughView()
            context.coordinator.view = view
            context.coordinator.install()
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.model = model
            context.coordinator.sidebarWidth = sidebarWidth
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

        func makeCoordinator() -> Coordinator { Coordinator(model: model, sidebarWidth: sidebarWidth) }

        @MainActor
        final class Coordinator {
            weak var view: NSView?
            var model: AppModel
            var sidebarWidth: CGFloat?
            private var monitor: Any?
            private var target = Target.none
            private var dx: CGFloat = 0
            private var dy: CGFloat = 0
            /// How far the fingers had moved when the swipe's direction was decided (so nothing jumps).
            private var deadZone: CGFloat = 0

            enum Target { case none, undecided, spaces, page, vertical }

            /// Distance (points) a page swipe needs before letting go navigates.
            static let pageThreshold: CGFloat = 150
            /// Distance a sidebar swipe needs before letting go switches Space.
            static let spaceThreshold: CGFloat = 70

            init(model: AppModel, sidebarWidth: CGFloat?) {
                self.model = model
                self.sidebarWidth = sidebarWidth
            }

            func install() {
                // Local monitors run on the main thread; the box carries the event across the isolation check.
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    let box = EventBox(event: event)
                    return MainActor.assumeIsolated { () -> EventBox in
                        guard let self, let event = box.event else { return box }
                        return EventBox(event: self.handle(event))
                    }.event
                }
            }

            func remove() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            private func handle(_ event: NSEvent) -> NSEvent? {
                guard let window = view?.window, event.window === window, event.hasPreciseScrollingDeltas,
                    event.momentumPhase.isEmpty, !model.isCommandBarPresented, !model.isWelcomePresented
                else { return event }
                switch event.phase {
                case .began:
                    target = .undecided
                    dx = 0
                    dy = 0
                case .changed:
                    return changed(event, in: window)
                case .ended, .cancelled:
                    finish(cancelled: event.phase == .cancelled)
                    target = .none
                default: break
                }
                return event
            }

            private func changed(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
                dx += event.scrollingDeltaX
                dy += event.scrollingDeltaY
                if target == .undecided, abs(dx) + abs(dy) > 8 {
                    if abs(dx) > abs(dy) * 1.6 {
                        deadZone = dx
                        let x = event.locationInWindow.x
                        target = (sidebarWidth.map { x < $0 } ?? false) ? .spaces : .page
                    } else {
                        target = .vertical
                    }
                }
                switch target {
                case .spaces:
                    let ids = model.state.spaces.map(\.id)
                    let index = ids.firstIndex(of: model.state.selectedSpaceID) ?? 0
                    // Rubber-band at the first and last Space.
                    let drag = dx - deadZone
                    let atEdge = (drag > 0 && index == 0) || (drag < 0 && index == ids.count - 1)
                    let limit = (sidebarWidth ?? 260) * 0.95
                    model.spaceSwipeOffset = atEdge ? drag / 4 : max(-limit, min(limit, drag))
                    return nil  // the sidebar only scrolls vertically, so the swipe is ours
                case .page:
                    let nav = model.pageNavigation
                    let wantsBack = dx > 0
                    guard wantsBack ? nav.canGoBack : nav.canGoForward else {
                        model.pageSwipeProgress = 0
                        return event
                    }
                    model.pageSwipeProgress = Double(max(-1, min(1, -dx / Self.pageThreshold)))
                    return event  // the page may scroll sideways too
                default:
                    return event
                }
            }

            private func finish(cancelled: Bool) {
                switch target {
                case .spaces:
                    let ids = model.state.spaces.map(\.id)
                    let index = ids.firstIndex(of: model.state.selectedSpaceID) ?? 0
                    let drag = model.spaceSwipeOffset
                    let next = drag < 0 ? index + 1 : index - 1
                    // One spring from where the fingers let go: the Spaces glide on (or back) without a jump.
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                        model.spaceSwipeOffset = 0
                        if !cancelled, abs(drag) > Self.spaceThreshold, ids.indices.contains(next) {
                            model.send(.space(.select(ids[next])))
                        }
                    }
                case .page:
                    let progress = model.pageSwipeProgress
                    if !cancelled, abs(progress) >= 1 {
                        if progress < 0 { model.goBack() } else { model.goForward() }
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.pageSwipeProgress = 0 }
                default: break
                }
            }
        }
    }
#endif

/// The arrow that slides in over the page's edge during a back/forward swipe. It follows the fingers and fills
/// when letting go would navigate. The page itself never moves.
struct SwipeArrow: View {
    let progress: Double
    /// How far the arrow travels in from the edge at full swipe.
    static let travel: CGFloat = 72

    var body: some View {
        let amount = min(1, abs(progress))
        let ready = abs(progress) >= 1
        let back = progress < 0
        Image(systemName: back ? "chevron.left" : "chevron.right")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(ready ? Color.white : Color.primary.opacity(0.75))
            .frame(width: 40, height: 40)
            .background {
                Circle().fill(ready ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .scaleEffect(ready ? 1.08 : 1)
            .opacity(min(1, amount * 2.5))
            // Starts just outside the edge and slides in.
            .offset(x: (back ? 1 : -1) * (-44 + Self.travel * amount))
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: ready)
            .environment(\.colorScheme, .light)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
