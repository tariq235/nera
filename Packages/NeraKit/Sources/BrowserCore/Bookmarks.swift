// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// One entry in a profile's bookmarks: a link or a folder of entries.
public struct Bookmark: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier.
    public var id: UUID
    /// Shown name.
    public var title: String
    /// Link target; `nil` for folders.
    public var url: URL?
    /// Folder contents; `nil` for links.
    public var children: [Bookmark]?
    /// When it was added.
    public var addedAt: Date?

    /// A link.
    public static func link(id: UUID, title: String, url: URL, addedAt: Date? = nil) -> Bookmark {
        Bookmark(id: id, title: title, url: url, children: nil, addedAt: addedAt)
    }

    /// A folder.
    public static func folder(id: UUID, title: String, children: [Bookmark] = [], addedAt: Date? = nil) -> Bookmark {
        Bookmark(id: id, title: title, url: nil, children: children, addedAt: addedAt)
    }

    /// Whether this is a folder.
    public var isFolder: Bool { children != nil }

    /// Every link inside (depth-first), including this one if it's a link.
    public var links: [Bookmark] { isFolder ? (children ?? []).flatMap(\.links) : [self] }

    /// Number of folders inside (not counting this one).
    public var folderCount: Int { (children ?? []).reduce(0) { $0 + ($1.isFolder ? 1 + $1.folderCount : 0) } }
}

extension [Bookmark] {
    /// Every link in the tree, depth-first.
    public var allLinks: [Bookmark] { flatMap(\.links) }

    /// Finds an entry anywhere in the tree.
    public func bookmark(id: UUID) -> Bookmark? {
        for b in self {
            if b.id == id { return b }
            if let found = b.children?.bookmark(id: id) { return found }
        }
        return nil
    }

    /// Removes an entry anywhere in the tree; returns it.
    @discardableResult
    mutating func removeBookmark(id: UUID) -> Bookmark? {
        if let i = firstIndex(where: { $0.id == id }) { return remove(at: i) }
        for i in indices where self[i].children != nil {
            if let removed = self[i].children?.removeBookmark(id: id) { return removed }
        }
        return nil
    }

    /// Changes an entry anywhere in the tree. Returns whether it was found.
    @discardableResult
    mutating func updateBookmark(id: UUID, _ change: (inout Bookmark) -> Void) -> Bool {
        for i in indices {
            if self[i].id == id {
                change(&self[i])
                return true
            }
            if self[i].children?.updateBookmark(id: id, change) == true { return true }
        }
        return false
    }

    /// Inserts into a folder (or the top level when `folderID` is nil). Returns false if the folder is missing.
    mutating func insertBookmark(_ bookmark: Bookmark, into folderID: UUID?) -> Bool {
        guard let folderID else {
            append(bookmark)
            return true
        }
        return updateBookmark(id: folderID) { folder in
            guard folder.isFolder else { return }
            folder.children?.append(bookmark)
        }
    }
}
