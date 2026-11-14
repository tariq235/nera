// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import SwiftUI

struct AddressPill: View {
    let host: any SidebarHost
    var siteInfo: (() -> AnyView)?
    @State private var copied = false
    @State private var isHovering = false

    private var isWebPage: Bool {
        guard let scheme = host.addressURL?.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    var body: some View {
        if host.isPageFullscreen {
            // Over a full-screen video, the address bar is the way back.
            Button {
                host.exitPageFullscreen()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 11, weight: .semibold))
                    Text("Exit Full Screen")
                    Spacer()
                }
                .font(.system(size: Metrics.addressFont))
                .padding(.horizontal, 10).frame(height: Metrics.addressHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .surface(.resting, cornerRadius: 10)
            .accessibilityIdentifier("sidebar.exitFullscreen")
        } else {
            addressBar
        }
    }

    /// Like Arc's: the site, then Copy Link and the site controls at the right.
    private var addressBar: some View {
        HStack(spacing: 0) {
            urlButton
            if isWebPage, host.addressURL != nil {
                Button {
                    Clipboard.copy(host.addressURL?.absoluteString ?? "")
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut(duration: 0.2)) { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(copied ? 0.8 : 0.55))
                        .frame(width: 26, height: Metrics.addressHeight)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help("Copy Link (⇧⌘C)")
                .opacity(showsButtons ? 1 : 0)
                .accessibilityLabel(copied ? "Link copied" : "Copy Link")
                .accessibilityIdentifier("sidebar.copyLink")
            }
            if let siteInfo, isWebPage {
                Button {
                    host.isSiteControlsPresented.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .frame(width: 28, height: Metrics.addressHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .opacity(showsButtons ? 1 : 0)
                .help("Site controls: share, customize, capture, permissions")
                .accessibilityLabel("Site controls")
                .accessibilityIdentifier("sidebar.siteInfo")
                .popover(
                    isPresented: Binding(get: { host.isSiteControlsPresented }, set: { host.isSiteControlsPresented = $0 }),
                    arrowEdge: .bottom
                ) { siteInfo() }
            }
        }
        .surface(.resting, cornerRadius: 10)
        .onHover { isHovering = $0 }
    }

    /// As in Arc, Copy Link and the site controls show while the pointer is on the address bar (or one is in use).
    private var showsButtons: Bool { isHovering || copied || host.isSiteControlsPresented }

    private var urlButton: some View {
        Button {
            host.showCommandBar(.currentTab)
        } label: {
            HStack(spacing: 6) {
                if DisplayURL.isInsecure(host.addressURL) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Not secure: this page doesn't use HTTPS")
                }
                let text = DisplayURL.short(host.addressURL)
                if text.isEmpty {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(text.isEmpty ? "Search or enter URL" : text)
                    .lineLimit(1)
                    .foregroundStyle(host.state.selectedTab == nil ? .secondary : Color.primary.opacity(0.8))
                Spacer()
            }
            .font(.system(size: Metrics.addressFont))
            .padding(.leading, 10).padding(.trailing, 6).frame(height: Metrics.addressHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.address")
    }
}
