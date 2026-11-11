// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import CommandBar
import Foundation
import PageLifecycle
import SecurityPolicy

/// The command bar's side of the app model: what Return does, and history to suggest.
extension AppModel {
    /// Opens command-bar input. Blocked URLs never become a tab.
    public func submitCommandBar(_ text: String) {
        isCommandBarPresented = false
        guard let result = Omnibox.parse(text, engine: state.settings.searchEngine) else { return }
        if case .block(let reason) = pages.policy.decide(result.url, trigger: .userTyped) {
            pages.lastBlocked = BlockedNavigation(url: result.url, reason: reason, tabID: state.selectedTabID ?? UUID())
            return
        }
        #if os(macOS)
            if commandBarDisposition == .littleWindow, !isPrivate { return openLittleWindow(result.url) }
        #endif
        send(.tab(.open(result.url, commandBarDisposition)))
    }

    /// Bookmark matches (first, up to 3) then history matches for the command bar (current profile).
    public func historySuggestions(for query: String) -> [CommandBarSuggestion] {
        guard let profile = state.currentProfile else { return [] }
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let bookmarks = profile.bookmarkTree.allLinks.filter { link in
            let haystack = (link.title + " " + (link.url?.absoluteString ?? "")).lowercased()
            return !words.isEmpty && words.allSatisfy { haystack.contains($0) }
        }
        var out = bookmarks.prefix(3).compactMap { b in b.url.map { CommandBarSuggestion(url: $0, title: b.title, isBookmark: true) } }
        let shown = Set(out.map(\.url))
        for entry in history?.search(query, profileID: profile.id, limit: 5) ?? [] where !shown.contains(entry.url) {
            out.append(CommandBarSuggestion(url: entry.url, title: entry.title, isBookmark: false))
        }
        return out
    }
}
