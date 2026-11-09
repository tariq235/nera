// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import SwiftUI

struct AddressPill: View {
    let host: any SidebarHost
    var siteInfo: (() -> AnyView)?
    @State private var isSiteInfoPresented = false

    private var isWebPage: Bool {
        guard let scheme = host.state.selectedTab?.url?.scheme?.lowercased() else { return false }
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
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .surface(.resting, cornerRadius: 10)
            .accessibilityIdentifier("sidebar.exitFullscreen")
        } else {
            addressBar
        }
    }

    private var addressBar: some View {
        HStack(spacing: 0) {
            if let siteInfo, isWebPage {
                let insecure = DisplayURL.isInsecure(host.state.selectedTab?.url)
                Button {
                    isSiteInfoPresented.toggle()
                } label: {
                    Image(systemName: insecure ? "exclamationmark.triangle.fill" : "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(insecure ? Color.orange : Color.primary.opacity(0.55))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(insecure ? "Not secure: this page doesn't use HTTPS. Site settings" : "Connection is secure. Site settings")
                .accessibilityLabel(insecure ? "Not secure. Site settings" : "Site settings")
                .accessibilityIdentifier("sidebar.siteInfo")
                .popover(isPresented: $isSiteInfoPresented, arrowEdge: .bottom) { siteInfo() }
            }
            urlButton
        }
        .surface(.resting, cornerRadius: 10)
    }

    private var urlButton: some View {
        Button {
            host.showCommandBar(.currentTab)
        } label: {
            HStack(spacing: 6) {
                if siteInfo == nil, DisplayURL.isInsecure(host.state.selectedTab?.url) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Not secure: this page doesn't use HTTPS")
                }
                let text = DisplayURL.short(host.state.selectedTab?.url)
                if text.isEmpty {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(text.isEmpty ? "Search or enter URL" : text)
                    .lineLimit(1)
                    .foregroundStyle(host.state.selectedTab == nil ? .secondary : .primary)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.leading, isWebPage && siteInfo != nil ? 0 : 10).padding(.trailing, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.address")
    }
}
