// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import EngineKit
import SwiftUI

/// Split View: the selected tab's split, every pane live. Click a pane's header to make it the active tab.
struct SplitViewContent: View {
    @Bindable var model: AppModel
    let panes: [(tab: BrowserCore.Tab, page: any WebPage)]
    let axis: Split.Axis

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            ForEach(Array(panes.enumerated()), id: \.element.tab.id) { index, pane in
                if index > 0 { Divider() }
                SplitPane(model: model, tab: pane.tab, page: pane.page, isSelected: pane.tab.id == model.state.selectedTabID, axis: axis)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("split.view")
    }
}

private struct SplitPane: View {
    let model: AppModel
    let tab: BrowserCore.Tab
    let page: any WebPage
    let isSelected: Bool
    let axis: Split.Axis

    var body: some View {
        VStack(spacing: 0) {
            header
            WebViewHost(
                page: page, isAccessible: (!isSelected || model.currentRequest == nil) && model.safety.dangerousSites[page.id] == nil
            )
            .id(page.id)
            .overlay { DangerousSiteOverlay(model: model, pageID: page.id) }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2).allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            SiteIcon(url: tab.url, size: 12, png: page.state.favicon)
            Text(tab.displayTitle).font(.caption).lineLimit(1)
            if !model.pages.requests(for: tab.id).isEmpty && !isSelected {
                Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange).font(.caption)
                    .help("This page is asking something; select it to answer")
            }
            Spacer(minLength: 4)
            Menu {
                Button(axis == .horizontal ? "Stack Vertically" : "Side by Side") {
                    model.send(.tab(.setSplitAxis(tab.id, axis == .horizontal ? .vertical : .horizontal)))
                }
                Button("Remove from Split View") { model.send(.tab(.removeFromSplit(tab.id))) }
                Button("Separate All") { model.send(.tab(.unsplit(tab.id))) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Split View options for \(tab.displayTitle)")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        .contentShape(Rectangle())
        .onTapGesture { model.send(.tab(.select(tab.id))) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("split.pane")
    }
}
