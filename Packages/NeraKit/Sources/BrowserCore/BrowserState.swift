// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// The whole persisted browser library. Pure value type: easy to test, diff, snapshot and sync.
public struct BrowserState: Codable, Equatable, Sendable {
    /// All profiles. Never empty.
    public var profiles: [Profile]
    /// All Spaces, in switcher order. Never empty.
    public var spaces: [Space]
    /// The focused Space.
    public var selectedSpaceID: UUID
    /// The focused tab, if any.
    public var selectedTabID: UUID?
    /// Closed and auto-archived tabs, newest first. Capped at `archiveLimit`.
    public var archive: [ArchivedTab]
    /// Stack for "Restore Last Closed Tab", newest first.
    public var recentlyClosed: [ArchivedTab]
    /// User settings.
    public var settings: Settings

    /// Maximum number of archive entries kept.
    public static let archiveLimit = 500
    /// Maximum depth of the ⇧⌘T stack.
    public static let recentlyClosedLimit = 50

    /// Creates a library.
    public init(
        profiles: [Profile], spaces: [Space], selectedSpaceID: UUID, selectedTabID: UUID? = nil,
        archive: [ArchivedTab] = [], recentlyClosed: [ArchivedTab] = [], settings: Settings = .default
    ) {
        self.profiles = profiles
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.selectedTabID = selectedTabID
        self.archive = archive
        self.recentlyClosed = recentlyClosed
        self.settings = settings
    }

    /// First-launch library: one profile, one Space, no tabs; the welcome screen shows.
    public static func initial(uuid: () -> UUID) -> BrowserState {
        let profile = Profile(id: uuid(), name: "Personal")
        let look = SpaceTheme.palette[0]
        let space = Space(id: uuid(), title: "Personal", icon: look.icon, theme: look.theme, profileID: profile.id)
        var settings = Settings.default
        settings.hasCompletedOnboarding = false
        return BrowserState(profiles: [profile], spaces: [space], selectedSpaceID: space.id, settings: settings)
    }

    // MARK: Queries

    /// The focused Space.
    public var selectedSpace: Space? { spaces.first { $0.id == selectedSpaceID } }

    /// Index of the focused Space in `spaces`.
    public var selectedSpaceIndex: Int? { spaces.firstIndex { $0.id == selectedSpaceID } }

    /// The profile a Space uses.
    public func profile(for space: Space) -> Profile? { profiles.first { $0.id == space.profileID } }

    /// The focused Space's profile.
    public var currentProfile: Profile? { selectedSpace.flatMap(profile(for:)) }

    /// The focused tab.
    public var selectedTab: Tab? { selectedTabID.flatMap(tab(withID:)) }

    /// The split showing the selected tab (Split View), if it's in one.
    public var selectedSplit: Split? {
        guard let id = selectedTabID, let space = selectedSpace else { return nil }
        return space.pinned.split(containing: id) ?? space.today.split(containing: id)
    }

    /// Finds a tab anywhere in the library (Spaces or Favorites).
    public func tab(withID id: UUID) -> Tab? { locate(id).map(\.tab) }

    /// Visual top-to-bottom order of tabs in a Space (pinned first, then today).
    public func orderedTabs(in space: Space) -> [Tab] {
        space.pinned.flatMap(\.tabs) + space.today.flatMap(\.tabs)
    }

    /// Where a tab currently lives.
    public enum Location: Equatable, Sendable {
        /// In a profile's Favorites.
        case favorite(profileID: UUID)
        /// In a section of a Space.
        case space(spaceID: UUID, section: Section)
    }

    /// The profile a tab belongs to (its Space's profile, or the profile whose Favorites hold it).
    public func profile(forTab id: UUID) -> Profile? {
        switch locate(id)?.location {
        case .favorite(let profileID): profiles.first { $0.id == profileID }
        case .space(let spaceID, _): spaces.first { $0.id == spaceID }.flatMap(profile(for:))
        case nil: nil
        }
    }

    /// Finds a tab and where it lives.
    public func locate(_ id: UUID) -> (tab: Tab, location: Location)? {
        for profile in profiles {
            if let t = profile.favorites.first(where: { $0.id == id }) { return (t, .favorite(profileID: profile.id)) }
        }
        for space in spaces {
            if let t = space.pinned.flatMap(\.tabs).first(where: { $0.id == id }) {
                return (t, .space(spaceID: space.id, section: .pinned))
            }
            if let t = space.today.flatMap(\.tabs).first(where: { $0.id == id }) { return (t, .space(spaceID: space.id, section: .today)) }
        }
        return nil
    }
}

// MARK: - Tree helpers

extension Array where Element == Node {
    /// Removes a tab anywhere in the tree. A split left with one tab collapses into a plain tab.
    mutating func removeTab(id: UUID) -> Tab? {
        for i in indices {
            switch self[i].kind {
            case .tab(let t) where t.id == id:
                remove(at: i)
                return t
            case .tab:
                continue
            case .folder(var folder):
                if let t = folder.children.removeTab(id: id) {
                    self[i].kind = .folder(folder)
                    return t
                }
            case .split(var split):
                if let idx = split.tabs.firstIndex(where: { $0.id == id }) {
                    let t = split.tabs.remove(at: idx)
                    if split.tabs.count == 1 { self[i] = .tab(split.tabs[0]) } else { self[i].kind = .split(split) }
                    return t
                }
            }
        }
        return nil
    }

    /// Replaces the node holding tab `id` (a plain tab or a split) with a split that also shows `added`.
    /// A split grows to at most 4 tabs. Returns false if `id` isn't here or the split is full.
    mutating func addToSplit(tabID id: UUID, _ added: Tab) -> Bool {
        for i in indices {
            switch self[i].kind {
            case .tab(let t) where t.id == id:
                self[i] = Node(id: UUID(), kind: .split(Split(tabs: [t, added])))
                return true
            case .tab:
                continue
            case .folder(var folder):
                if folder.children.addToSplit(tabID: id, added) {
                    self[i].kind = .folder(folder)
                    return true
                }
            case .split(var split):
                guard let idx = split.tabs.firstIndex(where: { $0.id == id }) else { continue }
                guard split.tabs.count < 4 else { return false }
                split.tabs.insert(added, at: idx + 1)
                self[i].kind = .split(split)
                return true
            }
        }
        return false
    }

    /// Changes the split containing tab `id`: `nil` from `change` separates it into plain tabs in place.
    @discardableResult
    mutating func updateSplit(containing id: UUID, _ change: (inout Split) -> Bool) -> Bool {
        for i in indices {
            switch self[i].kind {
            case .tab:
                continue
            case .folder(var folder):
                if folder.children.updateSplit(containing: id, change) {
                    self[i].kind = .folder(folder)
                    return true
                }
            case .split(var split):
                guard split.tabs.contains(where: { $0.id == id }) else { continue }
                if change(&split), split.tabs.count > 1 {
                    self[i].kind = .split(split)
                } else {
                    replaceSubrange(i...i, with: split.tabs.map(Node.tab))
                }
                return true
            }
        }
        return false
    }

    /// Takes tab `id` out of its split and places it right after the split. Returns false if it isn't in one.
    mutating func extractFromSplit(_ id: UUID) -> Bool {
        for i in indices {
            switch self[i].kind {
            case .tab:
                continue
            case .folder(var folder):
                if folder.children.extractFromSplit(id) {
                    self[i].kind = .folder(folder)
                    return true
                }
            case .split(var split):
                guard let idx = split.tabs.firstIndex(where: { $0.id == id }) else { continue }
                let tab = split.tabs.remove(at: idx)
                if split.tabs.count == 1 {
                    replaceSubrange(i...i, with: [.tab(split.tabs[0]), .tab(tab)])
                } else {
                    self[i].kind = .split(split)
                    insert(.tab(tab), at: i + 1)
                }
                return true
            }
        }
        return false
    }

    /// Removes the node with `id` (folder, split or tab node), or a single tab out of a split. Searches folders.
    mutating func removeNode(id: UUID) -> Node? {
        if let i = firstIndex(where: { $0.id == id }) { return remove(at: i) }
        for i in indices {
            if case .folder(var folder) = self[i].kind, let found = folder.children.removeNode(id: id) {
                self[i].kind = .folder(folder)
                return found
            }
        }
        return removeTab(id: id).map(Node.tab)
    }

    /// Whether a node or tab with `id` is anywhere in this tree.
    func containsNode(_ id: UUID) -> Bool {
        contains { node in
            if node.id == id || node.tabs.contains(where: { $0.id == id }) { return true }
            if case .folder(let folder) = node.kind { return folder.children.containsNode(id) }
            return false
        }
    }

    /// Inserts `node` before the node (or the split holding the tab) with `target`. Returns false if not found.
    mutating func insertNode(_ node: Node, before target: UUID) -> Bool {
        if let i = firstIndex(where: { $0.id == target || $0.tabs.contains(where: { $0.id == target }) && !$0.isFolder }) {
            insert(node, at: i)
            return true
        }
        for i in indices {
            if case .folder(var folder) = self[i].kind, folder.children.insertNode(node, before: target) {
                self[i].kind = .folder(folder)
                return true
            }
        }
        return false
    }

    /// Appends `node` to the folder `folderID`. Returns false if not found.
    mutating func appendNode(_ node: Node, toFolder folderID: UUID) -> Bool {
        for i in indices {
            guard case .folder(var folder) = self[i].kind else { continue }
            if self[i].id == folderID {
                folder.children.append(node)
                folder.isExpanded = true
                self[i].kind = .folder(folder)
                return true
            }
            if folder.children.appendNode(node, toFolder: folderID) {
                self[i].kind = .folder(folder)
                return true
            }
        }
        return false
    }

    /// The split containing tab `id`, if any.
    public func split(containing id: UUID) -> Split? {
        for node in self {
            switch node.kind {
            case .tab: continue
            case .folder(let folder): if let s = folder.children.split(containing: id) { return s }
            case .split(let split): if split.tabs.contains(where: { $0.id == id }) { return split }
            }
        }
        return nil
    }

    /// Applies `transform` to the tab with `id`. Returns true if found.
    @discardableResult
    mutating func updateTab(id: UUID, _ transform: (inout Tab) -> Void) -> Bool {
        for i in indices {
            switch self[i].kind {
            case .tab(var t) where t.id == id:
                transform(&t)
                self[i].kind = .tab(t)
                return true
            case .tab:
                continue
            case .folder(var folder):
                if folder.children.updateTab(id: id, transform) {
                    self[i].kind = .folder(folder)
                    return true
                }
            case .split(var split):
                if let idx = split.tabs.firstIndex(where: { $0.id == id }) {
                    transform(&split.tabs[idx])
                    self[i].kind = .split(split)
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    mutating func updateFolder(id: UUID, _ transform: (inout Folder) -> Void) -> Bool {
        for i in indices {
            if case .folder(var folder) = self[i].kind {
                if self[i].id == id {
                    transform(&folder)
                    self[i].kind = .folder(folder)
                    return true
                }
                if folder.children.updateFolder(id: id, transform) {
                    self[i].kind = .folder(folder)
                    return true
                }
            }
        }
        return false
    }
}

extension BrowserState {
    /// The innermost folder holding a tab in the selected Space (Space on the keyboard opens or closes it).
    public func folderID(containing tabID: UUID) -> UUID? {
        func search(_ nodes: [Node]) -> UUID? {
            for node in nodes {
                guard case .folder(let folder) = node.kind, node.tabs.contains(where: { $0.id == tabID }) else { continue }
                return search(folder.children) ?? node.id
            }
            return nil
        }
        guard let space = selectedSpace else { return nil }
        return search(space.pinned) ?? search(space.today)
    }
}
