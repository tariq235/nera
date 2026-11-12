// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

// MARK: - Engines (identity only)

/// Identifies a rendering engine by a stable string, for example `"webkit"` or `"chromium"`.
///
/// BrowserCore only *stores* the user's engine preference. It never depends on an engine: the
/// engine layer (`PageLifecycle.EngineRegistry`) resolves an `EngineID` to a concrete engine.
public struct EngineID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    /// The stable identifier. Must match `EngineKit.EngineDescriptor.id` of the engine it names.
    public var rawValue: String

    /// Creates an identifier from its stable string.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Apple's WebKit (iOS/iPadOS engine, macOS fallback).
    public static let webKit = EngineID(rawValue: "webkit")
    /// Chromium via CEF (macOS default).
    public static let chromium = EngineID(rawValue: "chromium")

    /// The raw identifier.
    public var description: String { rawValue }
}

// MARK: - Profiles

/// A profile owns an isolated website data store (cookies, storage, cache) and an engine choice.
/// Several Spaces can share one profile, e.g. "Work" and "Work – Research".
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier; also the key of the profile's website data store in every engine.
    public var id: UUID
    /// User-visible name.
    public var name: String
    /// Favorites are shown as a grid above the sidebar and are shared by every Space using this profile.
    public var favorites: [Tab]
    /// Preferred engine. `nil` means the platform default (Chromium on macOS, WebKit on iOS).
    /// Optional so libraries written before this field existed still decode.
    public var engine: EngineID?
    /// Remembered per-site permission decisions for this profile (SEC-040). Optional so libraries written
    /// before this field existed still decode; read it through ``sitePermission(origin:kind:)``.
    public var sitePermissions: [SitePermission]?
    /// Bookmarks. Optional so older libraries still decode; read through ``bookmarkTree``.
    public var bookmarks: [Bookmark]?

    /// Zoom chosen per site (host → factor), like Chrome. Optional so older libraries decode.
    public var siteZoom: [String: Double]?
    /// Engine chosen per site (``SiteEngines``): e.g. a video site sent to WebKit. Optional so older libraries decode.
    public var siteEngines: [String: EngineID]?
    /// SiteStyles per site (``SiteStyle/site(of:)`` → SiteStyle). Optional so older libraries decode.
    public var siteStyles: [String: SiteStyle]?

    /// The bookmark tree (empty when none).
    public var bookmarkTree: [Bookmark] { bookmarks ?? [] }

    /// The remembered decision for `origin` (e.g. `https://example.com`) and `kind`, if any.
    public func sitePermission(origin: String, kind: SitePermissionKind) -> SitePermissionSetting? {
        sitePermissions?.first { $0.origin == origin && $0.kind == kind }?.setting
    }

    /// Creates a profile.
    public init(id: UUID, name: String, favorites: [Tab] = [], engine: EngineID? = nil) {
        self.id = id
        self.name = name
        self.favorites = favorites
        self.engine = engine
    }
}

// MARK: - Spaces

/// A Space is a named, themed set of tabs. Each Space has a pinned section (kept)
/// and a "today" section (temporary, auto-archived after inactivity).
public struct Space: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier.
    public var id: UUID
    /// User-visible name.
    public var title: String
    /// Icon shown in the Space switcher.
    public var icon: SpaceIcon
    /// Colors used behind the sidebar and content.
    public var theme: SpaceTheme
    /// The profile whose website data and engine this Space uses.
    public var profileID: UUID
    /// Kept tabs, folders and splits. Closing a pinned tab only unloads it.
    public var pinned: [Node]
    /// Temporary tabs, newest first. Closing archives them; idle ones are archived automatically.
    public var today: [Node]
    /// Whether the pinned section is open or folded away (click the Space's name); nil, as in older libraries: open.
    public var pinnedFold: SectionFold?

    /// Whether the pinned section is folded away.
    public var isPinnedCollapsed: Bool { pinnedFold == .folded }

    /// Creates a Space.
    public init(
        id: UUID, title: String, icon: SpaceIcon = .symbol("circle.fill"), theme: SpaceTheme = .default,
        profileID: UUID, pinned: [Node] = [], today: [Node] = []
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.theme = theme
        self.profileID = profileID
        self.pinned = pinned
        self.today = today
    }
}

/// Our own theme model (hue-based). Colors are stored as numbers, never as presets copied from elsewhere.
public struct SpaceTheme: Codable, Hashable, Sendable {
    /// Base hue, 0...1.
    public var hue: Double
    /// Base saturation, 0...1.
    public var saturation: Double
    /// Light/dark preference for this Space.
    public var appearance: Appearance
    /// A second hue the backdrop blends into (nil: shades of `hue`).
    public var secondaryHue: Double?
    /// Film-grain strength on the backdrop, 0...1 (nil: none).
    public var grain: Double?
    /// The exact colors the Space had in the browser it was imported from (Arc), so it looks the same here. Edited
    /// themes drop them and use `hue` and `saturation`, which are set to match.
    public var exact: ExactColors?

    /// Appearance preference.
    public enum Appearance: String, Codable, Sendable {
        /// Follow the system setting.
        case system
        /// Always light.
        case light
        /// Always dark.
        case dark
    }

    /// The theme new Spaces start with.
    public static let `default` = SpaceTheme(hue: 0.62, saturation: 0.35, appearance: .system)

    /// Colors and icons handed to new Spaces in turn (and offered in Edit Space).
    public static let palette: [(theme: SpaceTheme, icon: SpaceIcon)] = [
        (SpaceTheme(hue: 0.66, saturation: 0.42, appearance: .system), .symbol("house.fill")),
        (SpaceTheme(hue: 0.07, saturation: 0.50, appearance: .system), .symbol("briefcase.fill")),
        (SpaceTheme(hue: 0.42, saturation: 0.40, appearance: .system), .symbol("leaf.fill")),
        (SpaceTheme(hue: 0.88, saturation: 0.38, appearance: .system), .symbol("heart.fill")),
        (SpaceTheme(hue: 0.53, saturation: 0.45, appearance: .system), .symbol("book.fill")),
        (SpaceTheme(hue: 0.76, saturation: 0.40, appearance: .system), .symbol("sparkles")),
        (SpaceTheme(hue: 0.13, saturation: 0.45, appearance: .system), .symbol("star.fill")),
        (SpaceTheme(hue: 0.0, saturation: 0.0, appearance: .system), .symbol("moon.fill")),
    ]

    /// Ready-made looks offered in the welcome screen and Edit Space: deep tones, then light ones.
    public static let swatches: [SpaceTheme] = [
        SpaceTheme(hue: 0.64, saturation: 0.45, appearance: .dark, secondaryHue: 0.70, grain: 0.35),  // midnight
        SpaceTheme(hue: 0.07, saturation: 0.30, appearance: .dark, secondaryHue: 0.04, grain: 0.35),  // espresso
        SpaceTheme(hue: 0.0, saturation: 0.0, appearance: .dark, grain: 0.3),  // graphite
        SpaceTheme(hue: 0.45, saturation: 0.55, appearance: .dark, secondaryHue: 0.50, grain: 0.35),  // forest
        SpaceTheme(hue: 0.04, saturation: 0.70, appearance: .dark, secondaryHue: 0.07, grain: 0.35),  // ember
        SpaceTheme(hue: 0.11, saturation: 0.65, appearance: .dark, secondaryHue: 0.13, grain: 0.35),  // bronze
        SpaceTheme(hue: 0.73, saturation: 0.55, appearance: .dark, secondaryHue: 0.80, grain: 0.35),  // violet
        SpaceTheme(hue: 0.20, saturation: 0.55, appearance: .light, secondaryHue: 0.30, grain: 0.25),  // lime
        SpaceTheme(hue: 0.75, saturation: 0.25, appearance: .light, secondaryHue: 0.92, grain: 0.25),  // lilac
        SpaceTheme(hue: 0.10, saturation: 0.12, appearance: .light, secondaryHue: 0.12, grain: 0.25),  // linen
        SpaceTheme(hue: 0.58, saturation: 0.30, appearance: .light, secondaryHue: 0.50, grain: 0.25),  // sky
        SpaceTheme(hue: 0.95, saturation: 0.25, appearance: .light, secondaryHue: 0.05, grain: 0.25),  // blush
    ]

    /// The theme with every value kept in 0...1.
    public var clamped: SpaceTheme {
        func unit(_ v: Double) -> Double { min(max(v, 0), 1) }
        return SpaceTheme(
            hue: unit(hue), saturation: unit(saturation), appearance: appearance, secondaryHue: secondaryHue.map(unit),
            grain: grain.map(unit), exact: exact)
    }

    /// This theme moved `t` (0...1) of the way toward `other`: hues go the short way round the color wheel, and
    /// light/dark switches halfway.
    public func blended(toward other: SpaceTheme, by t: Double) -> SpaceTheme {
        func wheel(_ a: Double, _ b: Double) -> Double {
            var d = b - a
            if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
            return (a + d * t + 1).truncatingRemainder(dividingBy: 1)
        }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        let colors: ExactColors? =
            switch (exact, other.exact) {
            case (let a?, let b?): a.blended(toward: b, by: t)
            case (let a?, nil): t < 0.5 ? a : nil
            case (nil, let b?): t < 0.5 ? nil : b
            case (nil, nil): nil
            }
        return SpaceTheme(
            hue: wheel(hue, other.hue), saturation: mix(saturation, other.saturation), appearance: t < 0.5 ? appearance : other.appearance,
            secondaryHue: wheel(secondaryHue ?? hue, other.secondaryHue ?? other.hue), grain: mix(grain ?? 0, other.grain ?? 0),
            exact: colors)
    }

    /// Whether two themes look the same (ignoring tiny slider differences).
    public func looksLike(_ other: SpaceTheme) -> Bool {
        abs(hue - other.hue) < 0.005 && abs(saturation - other.saturation) < 0.005 && appearance == other.appearance
            && abs((secondaryHue ?? hue) - (other.secondaryHue ?? other.hue)) < 0.005 && exact == other.exact
    }

    /// Creates a theme.
    public init(
        hue: Double, saturation: Double, appearance: Appearance, secondaryHue: Double? = nil, grain: Double? = nil,
        exact: ExactColors? = nil
    ) {
        self.hue = hue
        self.saturation = saturation
        self.appearance = appearance
        self.secondaryHue = secondaryHue
        self.grain = grain
        self.exact = exact
    }
}

// MARK: - Sidebar tree

/// The two sections of a Space.
public enum Section: String, Codable, Hashable, Sendable {
    /// Kept tabs.
    case pinned
    /// Temporary tabs.
    case today
}

/// One entry in a sidebar section: a tab, a folder of nodes, or a split view of tabs.
public struct Node: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier. For `.tab` nodes it equals the tab's ID.
    public var id: UUID
    /// What the node is.
    public var kind: Kind

    /// The node's content.
    public enum Kind: Codable, Hashable, Sendable {
        /// A single tab.
        case tab(Tab)
        /// A folder containing further nodes.
        case folder(Folder)
        /// Two or more tabs shown side by side.
        case split(Split)
    }

    /// Creates a node.
    public init(id: UUID, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Wraps a tab in a node with the same ID.
    public static func tab(_ tab: Tab) -> Node { Node(id: tab.id, kind: .tab(tab)) }

    /// Whether this is a folder.
    public var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    /// All tabs inside this node, depth-first.
    public var tabs: [Tab] {
        switch kind {
        case .tab(let t): [t]
        case .folder(let f): f.children.flatMap(\.tabs)
        case .split(let s): s.tabs
        }
    }
}

/// A browser tab as stored in the library. Live page state belongs to the engine layer.
public struct Tab: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier; also the ID of the tab's live page.
    public var id: UUID
    /// Last committed URL.
    public var url: URL?
    /// Last known page title.
    public var title: String
    /// For pinned tabs and favorites: the URL the tab returns to on "Reset Tab".
    public var homeURL: URL?
    /// Last time the user focused the tab. Drives auto-archiving and Space restore.
    public var lastActiveAt: Date
    /// Whether the user muted the tab.
    public var isMuted: Bool
    /// A name the user gave the tab (Rename…); shown instead of the page title, which keeps updating underneath.
    public var customTitle: String?
    /// An emoji the user chose as the tab's icon (Change Icon…), shown instead of the site's icon.
    public var customIcon: String?

    /// Creates a tab.
    public init(id: UUID, url: URL?, title: String = "", homeURL: URL? = nil, lastActiveAt: Date, isMuted: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.homeURL = homeURL
        self.lastActiveAt = lastActiveAt
        self.isMuted = isMuted
    }

    /// Title for display: the user's name for it, else the page title, else the host, else the URL, else "New Tab".
    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !title.isEmpty { return title }
        return url?.host() ?? url?.absoluteString ?? "New Tab"
    }
}

/// A named group of nodes.
public struct Folder: Codable, Hashable, Sendable {
    /// User-visible name.
    public var title: String
    /// Contents, in order.
    public var children: [Node]
    /// Whether the folder is expanded in the sidebar.
    public var isExpanded: Bool

    /// Creates a folder.
    public init(title: String, children: [Node] = [], isExpanded: Bool = true) {
        self.title = title
        self.children = children
        self.isExpanded = isExpanded
    }
}

/// Tabs shown side by side.
public struct Split: Codable, Hashable, Sendable {
    /// The tabs, in display order (at least two).
    public var tabs: [Tab]
    /// Layout direction.
    public var axis: Axis

    /// Layout direction of a split.
    public enum Axis: String, Codable, Sendable {
        /// Side by side.
        case horizontal
        /// Stacked.
        case vertical
    }

    /// Creates a split.
    public init(tabs: [Tab], axis: Axis = .horizontal) {
        self.tabs = tabs
        self.axis = axis
    }
}

// MARK: - Archive

/// A closed or auto-archived tab, kept so it can be found or restored later.
public struct ArchivedTab: Codable, Hashable, Identifiable, Sendable {
    /// The archived tab's ID.
    public var id: UUID { tab.id }
    /// The tab as it was when archived.
    public var tab: Tab
    /// The Space it came from.
    public var spaceID: UUID
    /// When it was archived.
    public var archivedAt: Date

    /// Creates an archive entry.
    public init(tab: Tab, spaceID: UUID, archivedAt: Date) {
        self.tab = tab
        self.spaceID = spaceID
        self.archivedAt = archivedAt
    }
}

// MARK: - Settings

/// User settings stored with the library.
public struct Settings: Codable, Hashable, Sendable {
    /// Unpinned tabs untouched for this long are archived (12 hours by default).
    public var archiveAfter: TimeInterval
    /// Engine used for command-bar searches.
    public var searchEngine: SearchEngine
    /// Upgrade http:// navigations to https:// (SR-001).
    public var httpsOnly: Bool
    /// Developer tools turned on by the user (SEC-056). Off by default and when missing from older libraries.
    public var isDeveloperToolsEnabled = false
    /// The welcome screen was finished. Libraries from before it existed count as finished.
    public var hasCompletedOnboarding = true
    /// Where links from other apps open when no rule matches.
    public var externalLinks = ExternalLinkTarget.littleWindow
    /// Rules that send links from other apps to a Space, checked in order.
    public var linkRoutes: [LinkRoute] = []
    /// Links that a Favorite or pinned tab opens in a new tab show in Peek instead.
    public var peekLinks = true
    /// A video playing with sound moves to a floating window (Picture in Picture) when you switch away from its tab.
    public var autoPictureInPicture = true
    /// Light or dark: the Mac's setting by default.
    public var appearance = AppearanceChoice.system

    private enum CodingKeys: String, CodingKey {
        case archiveAfter, searchEngine, httpsOnly
        case isDeveloperToolsEnabled = "developerTools"
        case hasCompletedOnboarding = "onboarded"
        case externalLinks, linkRoutes, peekLinks, appearance
        case autoPictureInPicture = "autoPiP"
    }

    /// Decodes settings; fields added after 0.1 default when missing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archiveAfter = try c.decode(TimeInterval.self, forKey: .archiveAfter)
        searchEngine = try c.decode(SearchEngine.self, forKey: .searchEngine)
        httpsOnly = try c.decode(Bool.self, forKey: .httpsOnly)
        isDeveloperToolsEnabled = try c.decodeIfPresent(Bool.self, forKey: .isDeveloperToolsEnabled) ?? false
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? true
        externalLinks = (try? c.decodeIfPresent(ExternalLinkTarget.self, forKey: .externalLinks)) ?? .littleWindow
        linkRoutes = (try? c.decodeIfPresent([LinkRoute].self, forKey: .linkRoutes)) ?? []
        peekLinks = try c.decodeIfPresent(Bool.self, forKey: .peekLinks) ?? true
        autoPictureInPicture = try c.decodeIfPresent(Bool.self, forKey: .autoPictureInPicture) ?? true
        appearance = (try? c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance)) ?? .system
    }

    /// Settings on first launch.
    public static let `default` = Settings(archiveAfter: 12 * 3600, searchEngine: .duckDuckGo, httpsOnly: true)

    /// Creates settings.
    public init(archiveAfter: TimeInterval, searchEngine: SearchEngine, httpsOnly: Bool) {
        self.archiveAfter = archiveAfter
        self.searchEngine = searchEngine
        self.httpsOnly = httpsOnly
    }
}

/// Nera's light or dark look (Settings › General).
public enum AppearanceChoice: String, Codable, Hashable, Sendable, CaseIterable {
    /// Follows the Mac (System Settings › Appearance).
    case system
    /// Always light.
    case light
    /// Always dark.
    case dark
    /// Each Space's own choice (Edit Space › Appearance).
    case perSpace
}

/// Where links from other apps open.
public enum ExternalLinkTarget: String, Codable, Hashable, Sendable, CaseIterable {
    /// A small window of their own; one click moves them into the browser.
    case littleWindow
    /// A new tab in the current Space.
    case currentSpace
}

/// An link rule: links from other apps that match `pattern` open in a Space.
public struct LinkRoute: Codable, Hashable, Sendable, Identifiable {
    /// Identity.
    public var id: UUID
    /// A site ("figma.com", which covers its subdomains) or a site and path prefix ("github.com/nera").
    public var pattern: String
    /// The Space the links go to.
    public var spaceID: UUID

    /// Creates a rule.
    public init(id: UUID, pattern: String, spaceID: UUID) {
        self.id = id
        self.pattern = pattern
        self.spaceID = spaceID
    }

    /// The pattern as stored: lowercased, no scheme, no "www.", no trailing slash.
    public static func normalize(_ raw: String) -> String {
        var p = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where p.hasPrefix(prefix) { p.removeFirst(prefix.count) }
        if p.hasPrefix("www.") { p.removeFirst(4) }
        while p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Whether a link matches: the site or one of its subdomains, and the path prefix if the rule has one.
    public func matches(_ url: URL) -> Bool {
        guard let rawHost = url.host()?.lowercased(), !pattern.isEmpty else { return false }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let parts = pattern.split(separator: "/", maxSplits: 1).map(String.init)
        let site = parts[0]
        guard host == site || host.hasSuffix("." + site) else { return false }
        guard parts.count > 1 else { return true }
        let path = url.path().lowercased()
        let prefix = "/" + parts[1]
        return path == prefix || path.hasPrefix(prefix + "/") || path.hasPrefix(prefix + "?")
    }
}

/// Where a link from another app goes.
public enum LinkDestination: Equatable, Sendable {
    /// A new tab in this Space.
    case space(UUID)
    /// A Little Window.
    case littleWindow
    /// A new tab in the current Space.
    case currentSpace

    /// Applies the user's rules (first match wins, ignoring rules for Spaces that no longer exist), then the
    /// default.
    public static func of(_ url: URL, in state: BrowserState) -> LinkDestination {
        let spaces = Set(state.spaces.map(\.id))
        if let route = state.settings.linkRoutes.first(where: { spaces.contains($0.spaceID) && $0.matches(url) }) {
            return .space(route.spaceID)
        }
        return state.settings.externalLinks == .littleWindow ? .littleWindow : .currentSpace
    }
}

/// A web search provider.
public struct SearchEngine: Codable, Hashable, Sendable {
    /// User-visible name.
    public var name: String
    /// URL template with a `{query}` placeholder.
    public var template: String

    /// DuckDuckGo (default).
    public static let duckDuckGo = SearchEngine(name: "DuckDuckGo", template: "https://duckduckgo.com/?q={query}")
    /// Google.
    public static let google = SearchEngine(name: "Google", template: "https://www.google.com/search?q={query}")
    /// Bing.
    public static let bing = SearchEngine(name: "Bing", template: "https://www.bing.com/search?q={query}")
    /// Brave Search.
    public static let brave = SearchEngine(name: "Brave Search", template: "https://search.brave.com/search?q={query}")
    /// Ecosia.
    public static let ecosia = SearchEngine(name: "Ecosia", template: "https://www.ecosia.org/search?q={query}")
    /// Kagi.
    public static let kagi = SearchEngine(name: "Kagi", template: "https://kagi.com/search?q={query}")
    /// Startpage.
    public static let startpage = SearchEngine(name: "Startpage", template: "https://www.startpage.com/do/search?q={query}")
    /// Perplexity.
    public static let perplexity = SearchEngine(name: "Perplexity", template: "https://www.perplexity.ai/search?q={query}")
    /// ChatGPT.
    public static let chatGPT = SearchEngine(name: "ChatGPT", template: "https://chatgpt.com/?q={query}")
    /// Yahoo.
    public static let yahoo = SearchEngine(name: "Yahoo", template: "https://search.yahoo.com/search?p={query}")

    /// The engines offered in Settings.
    public static let presets: [SearchEngine] = [google, duckDuckGo, bing, brave, ecosia, kagi, startpage, perplexity, chatGPT, yahoo]

    /// Creates a search engine.
    public init(name: String, template: String) {
        self.name = name
        self.template = template
    }

    /// The search URL for `query`, with the query safely percent-encoded.
    public func url(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }
}

/// Something a website can ask to use. Engine-neutral (EngineKit maps its request kinds onto these).
public enum SitePermissionKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Camera.
    case camera
    /// Microphone.
    case microphone
    /// Precise location.
    case location
    /// System notifications.
    case notifications
    /// Reading the clipboard.
    case clipboardRead
    /// Device motion and orientation (iOS).
    case motion
}

/// A remembered answer.
public enum SitePermissionSetting: String, Codable, Hashable, Sendable {
    /// Allowed without asking again.
    case allow
    /// Denied without asking again.
    case deny
}

/// One remembered decision: this origin may (not) use this kind, in one profile.
public struct SitePermission: Codable, Hashable, Sendable {
    /// The `origin` of a profile-wide default ("Don't allow sites to use your camera").
    public static let allSites = "*"

    /// Origin as `scheme://host[:port]`, or ``allSites`` for the profile's default.
    public var origin: String
    /// What it's about.
    public var kind: SitePermissionKind
    /// The decision.
    public var setting: SitePermissionSetting

    /// Creates a decision.
    public init(origin: String, kind: SitePermissionKind, setting: SitePermissionSetting) {
        self.origin = origin
        self.kind = kind
        self.setting = setting
    }
}
