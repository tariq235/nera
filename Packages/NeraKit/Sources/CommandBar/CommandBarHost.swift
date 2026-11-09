// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import Foundation

/// What the command bar needs from the app. Keeps the CommandBar module independent of the shell,
/// the engine and storage.
@MainActor
public protocol CommandBarHost: AnyObject {
    /// The library (for open-tab suggestions and the search engine setting).
    var state: BrowserState { get }
    /// Whether the bar opens a new tab (⌘T) or navigates the current one (⌘L).
    var commandBarDisposition: TabAction.Disposition { get }
    /// The selected tab's URL, pre-filled for ⌘L.
    var currentURLString: String { get }
    /// Opens the typed text (URL or search). The host applies the navigation policy.
    func submitCommandBar(_ text: String)
    /// Focuses an already-open tab.
    func switchToTab(_ id: UUID)
    /// Closes the bar without doing anything.
    func dismissCommandBar()
    /// Bookmarks and visited pages matching `query`, best first. Empty for private sessions.
    func historySuggestions(for query: String) -> [CommandBarSuggestion]
    /// A site's icon (PNG), if the browser has one.
    func commandBarIcon(for url: URL?) -> Data?
    /// The Space's theme: the highlighted row takes its color.
    var commandBarTheme: SpaceTheme? { get }
}

extension CommandBarHost {
    /// No icons by default (monograms are shown).
    public func commandBarIcon(for url: URL?) -> Data? { nil }
    /// The default theme by default.
    public var commandBarTheme: SpaceTheme? { nil }
}

/// A bookmark or history page offered by the command bar.
public struct CommandBarSuggestion: Equatable, Sendable {
    /// Where it goes.
    public var url: URL
    /// Its title.
    public var title: String
    /// A bookmark (star) rather than a history entry (clock).
    public var isBookmark: Bool

    /// Creates a suggestion.
    public init(url: URL, title: String, isBookmark: Bool) {
        self.url = url
        self.title = title
        self.isBookmark = isBookmark
    }
}
