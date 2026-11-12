// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Everything the user, the UI or the engine layer can do to the library.
///
/// Actions are grouped by domain so each domain's reducer is exhaustive and lives in its own file.
public enum Action: Equatable, Sendable {
    /// Tab actions (open, close, pin, …).
    case tab(TabAction)
    /// Space and folder actions.
    case space(SpaceAction)
    /// Library-wide actions (archiving, import, profile settings).
    case library(LibraryAction)
}

/// Actions on tabs.
public enum TabAction: Equatable, Sendable {
    /// Where a URL opens.
    public enum Disposition: Equatable, Sendable {
        /// A new tab at the top of Today, selected.
        case newTab
        /// Navigate the selected tab (falls back to a new tab if none is selected).
        case currentTab
        /// A new tab shown in Split View next to the selected tab.
        case splitWithCurrent
        /// A Little Window (File › New Little Window); a new tab where there are no Little Windows.
        case littleWindow
    }

    /// Drag and drop in the sidebar: move a tab, folder or split (by node or tab ID) in the selected Space.
    case moveNode(UUID, to: NodeDestination)
    /// Show tab `other` in Split View with `id` (both in the same Space). `other` moves into `id`'s split.
    case splitWith(UUID, other: UUID)
    /// Take a tab out of its split; a split left with one tab becomes a plain tab.
    case removeFromSplit(UUID)
    /// Separate every tab of the split containing this tab.
    case unsplit(UUID)
    /// Side by side or stacked, for the split containing this tab.
    case setSplitAxis(UUID, Split.Axis)
    /// Open `URL` with the given disposition.
    case open(URL, Disposition)
    /// A page opened a child page (e.g. `target=_blank` or an OAuth popup). The engine already created
    /// the page with this `id`; the library gets a tab for it next to its opener.
    case openChild(id: UUID, url: URL?, openerID: UUID, select: Bool)
    /// Focus a tab (also switches to its Space).
    case select(UUID)
    /// Deselect every tab (safe mode: nothing loads until the user picks a tab).
    case clearSelection
    /// Focus the tab `offset` positions away in the current Space (wraps around).
    case selectAdjacent(offset: Int)
    /// ⌘W. Today tabs are archived; pinned tabs and favorites are only unloaded.
    case close(UUID)
    /// Move between Today and Pinned (or out of Favorites).
    case togglePin(UUID)
    /// Navigate a pinned tab or favorite back to its home URL.
    case resetToHome(UUID)
    /// ⇧⌘T.
    case restoreLastClosed
    /// The engine reported a new committed URL and/or title.
    case didUpdate(UUID, url: URL?, title: String?)
    /// Move a tab into the current profile's Favorites.
    case addToFavorites(UUID)
    /// Move a tab to `index` of `section` in the current Space.
    case move(UUID, section: Section, index: Int)
    /// Name a tab (an empty name goes back to the page title).
    case rename(UUID, title: String)
    /// A new tab with the same page, just below the tab (or at the top of Today), selected.
    case duplicate(UUID)
    /// Move a tab to the top of another Space's Today (from its Space or Favorites). A selected tab is followed there.
    case moveToSpace(UUID, spaceID: UUID)
    /// ⌘Z: bring back what was closed last: the Today section a Clear emptied, or else the last closed tab.
    case undoClose
    /// Give a tab an emoji as its icon (nil: the site's icon again).
    case setIcon(UUID, emoji: String?)
    /// Mute or unmute a tab; it stays so when its page is reloaded, discarded or Nera restarts.
    case setMuted(UUID, Bool)
    /// A pinned tab or Favorite returns to the page it shows now from here on (Edit Pinned Page).
    case makeCurrentPageHome(UUID)
    /// Put a Today tab in Split View beside a copy of another tab's page (Peek's Split View: the Favorite or pinned
    /// tab that opened it stays where it is). The Today tab stays selected.
    case splitBesideCopy(UUID, of: UUID)
}

/// Where a dragged sidebar item lands.
public enum NodeDestination: Equatable, Sendable {
    /// Just before this node or tab (same folder or section).
    case before(UUID)
    /// At the end of a section.
    case endOf(Section)
    /// At the end of this folder.
    case intoFolder(UUID)
    /// At the end of Favorites (tabs only).
    case favorites
}

/// Actions on Spaces and folders.
public enum SpaceAction: Equatable, Sendable {
    /// Create a Space using the current profile, and switch to it.
    case create(title: String)
    /// Switch to a Space; its most recently used tab is selected.
    case select(UUID)
    /// Switch to the Space `offset` positions away (wraps around).
    case selectAdjacent(offset: Int)
    /// Move a Space to another profile (its pages reopen with that profile's cookies and engine).
    case setProfile(UUID, profileID: UUID)
    /// Create a Space in a specific profile, and switch to it.
    case createInProfile(title: String, profileID: UUID)
    /// Rename a Space (blank names are ignored).
    case rename(UUID, title: String)
    /// Delete a Space and discard its pages. The last Space can't be deleted.
    case delete(UUID)
    /// Add a folder to the current Space's pinned section.
    case createFolder(title: String)
    /// Expand or collapse a folder in the current Space.
    case toggleFolder(UUID)
    /// Rename a folder in the current Space (blank names are ignored).
    case renameFolder(UUID, title: String)
    /// Delete a folder; its tabs move to where the folder was.
    case deleteFolder(UUID)
    /// Archive every Today tab in the current Space.
    case clearToday
    /// Fold away or show a Space's pinned section.
    case togglePinnedSection(UUID)
    /// Change a Space's icon and/or colors (`nil` keeps the current one).
    case customize(UUID, icon: SpaceIcon?, theme: SpaceTheme?)
}

/// Library-wide actions.
public enum LibraryAction: Equatable, Sendable {
    /// Archive Today tabs idle for longer than `Settings.archiveAfter`. Run on launch and periodically.
    case archiveSweep
    /// Append imported Spaces (and Favorites for the first Space's profile), then switch to the first one.
    case importLibrary(spaces: [Space], favorites: [Tab])
    /// Merge archived tabs brought over from another browser (only for Spaces that exist), newest first, capped.
    case importArchive([ArchivedTab])
    /// Choose a profile's engine (`nil` = platform default). Live pages of that profile are discarded
    /// so they reopen in the new engine.
    case setEngine(profileID: UUID, engine: EngineID?)
    /// Remember (or, with `nil`, forget) a site's permission decision in a profile (SEC-040).
    case setSitePermission(profileID: UUID, origin: String, kind: SitePermissionKind, setting: SitePermissionSetting?)
    /// Forget every remembered decision for `origin` in a profile, or all of them when `origin` is `nil`.
    case resetSitePermissions(profileID: UUID, origin: String?)
    /// Add a profile with its first Space (named like the profile), and switch to it.
    case createProfile(name: String)
    /// Rename a profile (blank names are ignored).
    case renameProfile(UUID, name: String)
    /// Delete a profile, its Spaces, Favorites and website data. The last profile can't be deleted.
    case deleteProfile(UUID)
    /// Remember a site's zoom in a profile (`nil` or 1.0 forgets it).
    case setSiteZoom(profileID: UUID, host: String, factor: Double?)
    /// Choose the engine for a site in a profile (`nil` returns it to the default).
    case setSiteEngine(profileID: UUID, site: String, EngineID?)
    /// Save a site's SiteStyle in a profile (`nil` deletes it).
    case setSiteStyle(profileID: UUID, site: String, SiteStyle?)
    /// Turn developer tools on or off (SEC-056).
    case setDeveloperTools(Bool)
    /// Pick the search engine used by the address bar.
    case setSearchEngine(SearchEngine)
    /// How long unpinned tabs stay before they're archived.
    case setArchiveAfter(TimeInterval)
    /// Where links from other apps open by default.
    case setExternalLinks(ExternalLinkTarget)
    /// Add an link rule (ignored if the pattern is empty or the Space doesn't exist).
    case addLinkRoute(pattern: String, spaceID: UUID)
    /// Remove an link rule.
    case removeLinkRoute(UUID)
    /// Turn Peek for links from Favorites and pinned tabs on or off.
    case setPeekLinks(Bool)
    /// Turn Picture in Picture for videos when you switch tabs on or off.
    case setAutoPictureInPicture(Bool)
    /// Light, dark, the Mac's setting, or each Space's.
    case setAppearance(AppearanceChoice)
    /// Change a profile's bookmarks.
    case bookmarks(profileID: UUID, BookmarkAction)
    /// The welcome screen was finished or skipped; it doesn't show again.
    case completeOnboarding
}

/// Changes to a profile's bookmark tree.
public enum BookmarkAction: Equatable, Sendable {
    /// Add a link to a folder (top level when `folderID` is nil). Ignored if the URL is already bookmarked there.
    case add(title: String, url: URL, folderID: UUID?)
    /// Add an empty folder.
    case addFolder(title: String, folderID: UUID?)
    /// Rename a link or folder (blank names are ignored).
    case rename(UUID, title: String)
    /// Delete a link, or a folder with everything in it.
    case delete(UUID)
    /// Move an entry into a folder (top level when nil). Moving a folder into itself is ignored.
    case move(UUID, toFolder: UUID?)
    /// Add imported bookmarks as one folder (e.g. "Imported from Chrome"), or at the top level when `folderTitle` is nil.
    case importTree([Bookmark], folderTitle: String?)
}

/// Side effects the store hands to the engine layer. The reducer itself never touches an engine.
public enum Effect: Hashable, Sendable {
    /// Load `url` in the tab's page (if the page is live; otherwise it loads when first shown).
    case load(tabID: UUID, url: URL)
    /// Destroy the tab's live page to free memory. The tab itself stays in the library.
    case discardPage(tabID: UUID)
    /// Delete a removed profile's website data (cookies, storage, cache) in every engine, and its history.
    case removeProfileData(profileID: UUID)
}

/// Injected sources of time and identity, so reducers are deterministic in tests.
public struct ReducerEnvironment: Sendable {
    /// Current time.
    public var now: @Sendable () -> Date
    /// New unique identifier.
    public var uuid: @Sendable () -> UUID

    /// Creates an environment.
    public init(now: @escaping @Sendable () -> Date, uuid: @escaping @Sendable () -> UUID) {
        self.now = now
        self.uuid = uuid
    }

    /// The real clock and random UUIDs.
    public static let live = ReducerEnvironment(now: { Date() }, uuid: { UUID() })
}
