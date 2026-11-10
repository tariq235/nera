// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import EngineKit
import SecurityPolicy
public import SwiftUI

/// Peek: a link from a Favorite or pinned tab, over the current page, laid out like Arc's (measured): the page in
/// the middle at nearly full height, the rest washed in the Space's selection color, and round buttons beside it:
/// Close (Esc, or a click outside), Open as Tab (⌘O), and Split View. The address pill shows the Peek page's site.
struct PeekView: View {
    @Bindable var model: AppModel
    let page: any WebPage

    var body: some View {
        GeometryReader { geo in
            let inset = max(48, geo.size.width * 0.085)
            ZStack(alignment: .topLeading) {
                Theme.focus(for: model.displayedTheme).opacity(0.97)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closePeek() }
                    .accessibilityHidden(true)
                WebViewHost(page: page, isAccessible: model.safety.dangerousSites[page.id] == nil)
                    .overlay { PendingRequest(model: model, pageID: page.id) }
                    .overlay { DangerousSiteOverlay(model: model, pageID: page.id) }
                    .overlay(alignment: .top) { PageProgressBar(page: page) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.08)))
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
                    .frame(width: max(geo.size.width - inset * 2, 0), height: max(geo.size.height - 12, 0))
                    .offset(x: inset, y: 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Peek")
                    .accessibilityIdentifier("peek")
                VStack(spacing: 9) {
                    PeekCircleButton(symbol: "xmark", help: "Close (Esc)", theme: model.displayedTheme) { model.closePeek() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close Peek")
                        .accessibilityIdentifier("peek.close")
                    PeekCircleButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open as Tab (⌘O)", theme: model.displayedTheme) {
                        model.openPeekAsTab()
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityLabel("Open as Tab")
                    .accessibilityIdentifier("peek.openAsTab")
                    PeekCircleButton(symbol: "rectangle.split.2x1", help: "Open in Split View", theme: model.displayedTheme) {
                        model.openPeekInSplitView()
                    }
                    .accessibilityLabel("Open in Split View")
                    .accessibilityIdentifier("peek.splitView")
                }
                .offset(x: geo.size.width - inset + 11, y: 14)
            }
        }
    }
}

/// One of Peek's round buttons: white, with the icon in the Space's deep color (Arc's look).
struct PeekCircleButton: View {
    let symbol: String
    let help: String
    let theme: SpaceTheme?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.deepTone(for: theme))
                .frame(width: 27, height: 27)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(isHovering ? 0.25 : 0.15), radius: isHovering ? 4 : 2, y: 1)
                .scaleEffect(isHovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
    }
}

/// The first thing a page outside the tab list is waiting on (a dialog, a permission…), drawn over its page.
struct PendingRequest: View {
    let model: AppModel
    let pageID: UUID

    var body: some View {
        if let request = model.pages.requests(for: pageID).first {
            PageRequestView(request: request, model: model).id(request.id)
        }
    }
}

/// A page's icon and address above it, with buttons on the right (Peek, Little Windows).
struct PageBar<Buttons: View>: View {
    let page: any WebPage
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(url: page.state.url, size: 13, png: page.state.favicon)
            Text(page.state.url.map { DisplayURL.short($0) } ?? "")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if page.state.isLoading { ProgressView().controlSize(.mini) }
            Spacer(minLength: 8)
            buttons()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }
}

/// The small buttons in Peek and Little Windows.
struct PeekButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, prominent ? 10 : 0)
            .frame(minWidth: 26, minHeight: 26)
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.75))
            .background {
                if prominent {
                    Capsule().fill(Color.accentColor)
                } else {
                    Circle().fill(.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

#if os(macOS)
    /// A Little Window: a link from another app in a small window of its own. "Open in Nera" moves it into the
    /// browser as a tab, as it is (nothing reloads); closing the window throws it away.
    public struct LittleWindowView: View {
        @Bindable var model: AppModel
        let id: UUID
        @Environment(\.dismiss) private var dismiss

        /// Creates the window content for the Little Window `id`.
        public init(model: AppModel, id: UUID) {
            self.model = model
            self.id = id
        }

        /// The window content.
        public var body: some View {
            Group {
                if let page = model.littlePage(id) {
                    VStack(spacing: 0) {
                        ZStack {
                            TitleBarArea()
                            PageBar(page: page) {
                                Button {
                                    Clipboard.copy(page.state.url?.absoluteString ?? "")
                                } label: {
                                    Image(systemName: "link").font(.system(size: 11, weight: .bold))
                                }
                                .buttonStyle(PeekButtonStyle(prominent: false))
                                .help("Copy Link")
                                .accessibilityLabel("Copy Link")
                                Button {
                                    model.moveLittleWindowToBrowser(id)
                                    dismiss()
                                } label: {
                                    Label("Open in Nera", systemImage: "arrow.up.forward.app")
                                }
                                .buttonStyle(PeekButtonStyle(prominent: true))
                                .keyboardShortcut("o", modifiers: .command)
                                .help("Move this page into the browser as a tab (⌘O)")
                                .accessibilityIdentifier("little.open")
                            }
                            .padding(.leading, 70)  // the window's buttons
                        }
                        .frame(height: 38)
                        WebViewHost(page: page, isAccessible: model.safety.dangerousSites[id] == nil)
                            .overlay { PendingRequest(model: model, pageID: id) }
                            .overlay { DangerousSiteOverlay(model: model, pageID: id) }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding([.horizontal, .bottom], 7)
                    }
                    .ignoresSafeArea(.container, edges: .top)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Theme.background(for: model.state.selectedSpace?.theme))
            .preferredColorScheme(model.preferredColorScheme)
            .frame(minWidth: 480, minHeight: 360)
            .onDisappear { model.closeLittleWindow(id) }
            .accessibilityIdentifier("littleWindow")
        }
    }
#endif
