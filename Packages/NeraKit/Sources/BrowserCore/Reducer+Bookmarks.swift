// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

extension Reducer {
    static func reduceBookmarks(_ state: inout BrowserState, _ profileID: UUID, _ action: BookmarkAction, _ env: ReducerEnvironment)
        -> [Effect]
    {
        guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }) else { return [] }
        var tree = state.profiles[pi].bookmarkTree
        switch action {
        case .add(let title, let url, let folderID):
            let siblings = folderID.flatMap { tree.bookmark(id: $0)?.children } ?? (folderID == nil ? tree : [])
            guard !siblings.contains(where: { $0.url == url }) else { return [] }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = tree.insertBookmark(
                .link(id: env.uuid(), title: name.isEmpty ? (url.host() ?? url.absoluteString) : name, url: url, addedAt: env.now()),
                into: folderID)
        case .addFolder(let title, let folderID):
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return [] }
            _ = tree.insertBookmark(.folder(id: env.uuid(), title: name, addedAt: env.now()), into: folderID)
        case .rename(let id, let title):
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return [] }
            tree.updateBookmark(id: id) { $0.title = name }
        case .delete(let id):
            tree.removeBookmark(id: id)
        case .move(let id, let folderID):
            guard let moving = tree.bookmark(id: id) else { return [] }
            if let folderID {
                // Not into itself or one of its own subfolders, and only into folders.
                guard folderID != id, moving.children?.bookmark(id: folderID) == nil, tree.bookmark(id: folderID)?.isFolder == true
                else { return [] }
            }
            tree.removeBookmark(id: id)
            _ = tree.insertBookmark(moving, into: folderID)
        case .importTree(let imported, let folderTitle):
            guard !imported.isEmpty else { return [] }
            if let folderTitle {
                tree.append(.folder(id: env.uuid(), title: folderTitle, children: imported, addedAt: env.now()))
            } else {
                tree.append(contentsOf: imported)
            }
        }
        state.profiles[pi].bookmarks = tree.isEmpty ? nil : tree
        return []
    }
}
