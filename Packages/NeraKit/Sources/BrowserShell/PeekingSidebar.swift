// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import Sidebar
import SwiftUI

/// The browser's sidebar, with the update card and what's playing at its foot.
struct BrowserSidebar: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            SidebarView(
                host: model, accessory: AnyView(SidebarAccessories(model: model)),
                siteInfo: { AnyView(SiteInfoView(model: model)) },
                nowPlaying: AnyView(
                    VStack(spacing: 8) {
                        UpdateCard(model: model)
                        MiniPlayer(model: model)
                    })
            )
        }
        // White text and controls over Spaces whose colors came from Arc with white content (the backdrop behind
        // keeps the window's appearance).
        .environment(\.colorScheme, Theme.contentScheme(for: model.displayedTheme, in: scheme))
    }
}

#if os(macOS)
    /// With the sidebar hidden, or over a full-screen video, resting the pointer on the left edge slides the sidebar
    /// in over the page; it slides away when the pointer leaves it.
    struct PeekingSidebar: View {
        @Bindable var model: AppModel
        let width: CGFloat

        var body: some View {
            if model.isSidebarPeeking {
                BrowserSidebar(model: model)
                    .frame(width: width)
                    .padding(.top, 4)
                    .background(Theme.background(for: model.state.selectedSpace?.theme))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.28), radius: 24, x: 6)
                    .padding(.vertical, 6).padding(.leading, 6)
                    .onHover { inside in if !inside { model.isSidebarPeeking = false } }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                Color.clear.frame(width: 6).contentShape(Rectangle())
                    .onHover { inside in if inside { model.isSidebarPeeking = true } }
            }
        }
    }
#endif
