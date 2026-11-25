// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import BrowserCore
    import DesignSystem
    import SwiftUI

    /// Over the page while a tab is dragged from the sidebar, as in Arc: hold it over the left or right half and the
    /// page makes room on that side for it; drop it there to show both in Split View.
    struct SplitDropZone: View {
        @Bindable var model: AppModel
        let dragged: UUID
        let beside: UUID
        @State private var side: Side?

        enum Side { case leading, trailing }

        var body: some View {
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: side == .leading ? .leading : .trailing) {
                    if let side {
                        // The page's side, dimmed a little: it's about to move over.
                        Rectangle().fill(.black.opacity(0.08))
                        placeholder
                            .frame(width: half - 12)
                            .padding(side == .leading ? .leading : .trailing, 8)
                            .padding(.vertical, 8)
                            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.spring(response: 0.3, dampingFraction: 0.86), value: side)
                .allowsHitTesting(false)
                .overlay {
                    DropCatcher(
                        accepts: dragged.uuidString,
                        hover: { fraction in side = fraction.map { $0 < 0.5 ? .leading : .trailing } },
                        drop: { fraction in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                model.send(.tab(.dropIntoSplit(dragged, beside: beside, leading: fraction < 0.5)))
                            }
                        })
                }
            }
            .accessibilityHidden(true)  // a drag target only; Split View is in the tab menu for keyboard and VoiceOver
        }

        /// Where the dragged tab will go: its icon and title on a glass panel.
        private var placeholder: some View {
            let tab = model.state.tab(withID: dragged)
            return RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2))
                .overlay {
                    VStack(spacing: 10) {
                        SiteIcon(url: tab?.url, size: 28, png: tab.flatMap { model.favicon(for: $0) })
                        Text(tab?.displayTitle ?? "").font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
    }

    /// Takes the drag in AppKit, above the page's own view (which would otherwise take a dropped string itself).
    /// Reports where across the page the pointer is (0 at the left edge, 1 at the right; nil when it leaves).
    private struct DropCatcher: NSViewRepresentable {
        let accepts: String
        let hover: (CGFloat?) -> Void
        let drop: (CGFloat) -> Void

        func makeNSView(context: Context) -> Catcher {
            let view = Catcher()
            view.registerForDraggedTypes([.string])
            return view
        }

        func updateNSView(_ view: Catcher, context: Context) {
            view.accepts = accepts
            view.hover = hover
            view.drop = drop
        }

        final class Catcher: NSView {
            var accepts = ""
            var hover: (CGFloat?) -> Void = { _ in }
            var drop: (CGFloat) -> Void = { _ in }

            private func fraction(_ info: any NSDraggingInfo) -> CGFloat {
                let point = convert(info.draggingLocation, from: nil)
                return bounds.width > 0 ? point.x / bounds.width : 0.5
            }

            private func isOurs(_ info: any NSDraggingInfo) -> Bool {
                info.draggingPasteboard.string(forType: .string) == accepts
            }

            override func draggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(info) }

            override func draggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
                guard isOurs(info) else { return [] }
                hover(fraction(info))
                return .move
            }

            override func draggingExited(_ info: (any NSDraggingInfo)?) { hover(nil) }

            override func performDragOperation(_ info: any NSDraggingInfo) -> Bool {
                guard isOurs(info) else { return false }
                hover(nil)
                drop(fraction(info))
                return true
            }
        }
    }
#endif
