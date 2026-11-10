// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import SwiftUI

/// The command bar's inline completion and its rows.
extension CommandBarView {
    /// The site the text completes to inline ("you" → "youtube.com"), from history and open tabs; none right after a
    /// deletion, so backspacing over a completion doesn't bring it back.
    var completion: String? {
        guard !lastEditWasDeletion else { return nil }
        let open = host.state.spaces.flatMap { host.state.orderedTabs(in: $0) }.compactMap(\.url)
        let visited = host.historySuggestions(for: text.trimmingCharacters(in: .whitespaces).lowercased()).map(\.url)
        return SiteCompletion.complete(text, candidates: visited + open)
    }

    /// The completed site's icon, or a magnifying glass.
    @ViewBuilder var fieldIcon: some View {
        if let site = completion, let url = URL(string: "https://\(site)/") {
            SiteIcon(url: url, size: 17, png: host.commandBarIcon(for: url))
        } else {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 20).accessibilityHidden(true)
        }
    }

    /// One suggestion, laid out like Arc's (measured): the site's icon (on a white tile when highlighted), its title
    /// and its address cut in the middle, and "Switch to Tab" for open tabs. The highlight is the Space's selection
    /// color.
    func row(_ s: Suggestion, isHighlighted: Bool) -> some View {
        let isSwitch = if case .switchTo = s.kind { true } else { false }
        return HStack(spacing: 9) {
            Group {
                if let url = s.url {
                    SiteIcon(url: url, size: 15, png: host.commandBarIcon(for: url))
                } else {
                    Image(systemName: s.symbol).font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                }
            }
            .frame(width: 25, height: 25)
            .background(isHighlighted && s.url != nil ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack(spacing: 5) {
                Text(s.title).fontWeight(.medium).lineLimit(1).layoutPriority(1)
                if !isSwitch, let url = s.url, case let detail = DisplayURL.detailed(url), detail != s.title {
                    Text("— \(detail)").foregroundStyle(isHighlighted ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .font(.system(size: 14))
            Spacer(minLength: 12)
            if isSwitch {
                Text("Switch to Tab").font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                    .background(
                        isHighlighted ? Color.white : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: Self.rowHeight)
        .background(
            isHighlighted ? Theme.focus(for: host.commandBarTheme) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// → or Tab: the field takes the inline completion.
    func acceptCompletion() -> KeyPress.Result {
        guard let site = completion, site.count > text.count else { return .ignored }
        text = site
        return .handled
    }

}
