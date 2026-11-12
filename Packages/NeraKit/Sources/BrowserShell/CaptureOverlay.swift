// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import SwiftUI

    /// File › Capture… (⇧⌘2): over the page, drag to choose an area (the rest dims); a click takes all that's on
    /// screen; Esc cancels.
    struct CaptureOverlay: View {
        static let hint = "Drag to capture an area, or click to capture the page · Esc to cancel"
        @Bindable var model: AppModel
        @State private var start: CGPoint?
        @State private var current: CGPoint?

        private var selection: CGRect? {
            guard let start, let current else { return nil }
            return CGRect(
                x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Dim everything but the selection (cut out of the dimming).
                    Color.black.opacity(0.32)
                        .mask {
                            Rectangle()
                                .overlay(alignment: .topLeading) {
                                    if let selection {
                                        Rectangle().frame(width: selection.width, height: selection.height)
                                            .offset(x: selection.minX, y: selection.minY)
                                            .blendMode(.destinationOut)
                                    }
                                }
                                .compositingGroup()
                        }
                    if let selection {
                        Rectangle().strokeBorder(.white, lineWidth: 1.5)
                            .frame(width: selection.width, height: selection.height)
                            .offset(x: selection.minX, y: selection.minY)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                    Text(Self.hint)
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if start == nil { start = drag.startLocation }
                            current = drag.location
                        }
                        .onEnded { _ in
                            let area = selection.flatMap {
                                $0.width < 4 || $0.height < 4 ? nil : $0.intersection(CGRect(origin: .zero, size: geo.size))
                            }
                            start = nil
                            current = nil
                            model.finishCapture(area, in: geo.size)
                        }
                )
                .onHover { inside in inside ? NSCursor.crosshair.push() : NSCursor.pop() }
                .background {
                    Button("Cancel Capture") { model.isCapturing = false }.keyboardShortcut(.cancelAction).hidden()
                }
                .accessibilityElement()
                .accessibilityLabel("Capture: drag over the page to choose an area")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityIdentifier("capture.overlay")
            }
        }
    }
#endif
