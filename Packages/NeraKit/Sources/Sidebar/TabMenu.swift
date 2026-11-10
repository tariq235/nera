// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

/// A tab's menu, in Arc's order: Copy Link and Share; Change Icon, Rename, Mute, Customize Page and Edit Pinned Page;
/// Split View, Duplicate and Move to; then closing, and Remove Favorite or Pin/Unpin.
struct TabMenu: View {
    let host: any SidebarHost
    let tab: Tab
    /// Shows "Rename…" (views that can show the rename dialog).
    var rename: (() -> Void)?
    /// Shows "Change Icon…" (views that can show the icon picker).
    var changeIcon: (() -> Void)?

    var body: some View {
        let location = host.state.locate(tab.id)?.location
        let isFavorite: Bool = if case .favorite? = location { true } else { false }
        let isPinned: Bool = if case .space(_, .pinned)? = location { true } else { isFavorite }
        Button("Copy Link") { Clipboard.copy(tab.url?.absoluteString ?? "") }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(tab.url == nil)
        if let url = tab.url {
            ShareLink(item: url) { Text("Share") }
        }
        Divider()
        if let changeIcon { Button("Change Icon…", action: changeIcon) }
        if let rename { Button("Rename…", action: rename) }
        let audio = host.audio(of: tab.id)
        Button(audio.muted ? "Unmute" : "Mute") { host.toggleMute(tab.id) }
            .disabled(!audio.playing && !audio.muted)
        Button("Customize Page…") { host.customizePage(tab.id) }
            .disabled(tab.url == nil || host.isPrivateSession)
        if isPinned {
            Menu("Edit Pinned Page") {
                Button("Use the Current Page") { host.send(.tab(.makeCurrentPageHome(tab.id))) }
                    .disabled(tab.url == nil || tab.url == tab.homeURL)
                Button("Go Back to the Pinned Page") { host.send(.tab(.resetToHome(tab.id))) }
                    .disabled(tab.homeURL == nil || tab.url == tab.homeURL)
            }
        }
        Divider()
        Button("Add Split View") { host.addSplitView(tab.id) }
            .disabled(tab.url == nil || host.isPrivateSession)
        if let selected = host.state.selectedTabID, selected != tab.id, !isFavorite {
            Button("Split View with Current Tab") { host.send(.tab(.splitWith(selected, other: tab.id))) }
        }
        if host.state.selectedSpace.map({ ($0.pinned + $0.today).split(containing: tab.id) != nil }) == true {
            Button("Remove from Split View") { host.send(.tab(.removeFromSplit(tab.id))) }
        }
        if tab.url != nil { Button("Duplicate") { host.send(.tab(.duplicate(tab.id))) } }
        moveTo(location: location, isFavorite: isFavorite)
        Divider()
        Button("Close Tab") { host.send(.tab(.close(tab.id))) }
            .keyboardShortcut("w", modifiers: .command)
        if isFavorite {
            Button("Remove Favorite") { host.send(.tab(.togglePin(tab.id))) }
        } else {
            Button(isPinned ? "Unpin" : "Pin") { host.send(.tab(.togglePin(tab.id))) }
        }
    }

    /// Move to: Favorites, and the other Spaces.
    @ViewBuilder private func moveTo(location: BrowserState.Location?, isFavorite: Bool) -> some View {
        let otherSpaces = host.state.spaces.filter { space in
            if case .space(let id, _)? = location { return space.id != id }
            return true
        }
        if !host.isPrivateSession, !isFavorite || !otherSpaces.isEmpty {
            Menu("Move to") {
                if !isFavorite {
                    Button {
                        host.send(.tab(.addToFavorites(tab.id)))
                    } label: {
                        Label("Favorites", systemImage: "star")
                    }
                }
                ForEach(otherSpaces) { space in
                    Button {
                        host.send(.tab(.moveToSpace(tab.id, spaceID: space.id)))
                    } label: {
                        Label {
                            Text(space.title)
                        } icon: {
                            SpaceIconView(icon: space.icon)
                        }
                    }
                }
            }
        }
    }
}

/// A Favorite: its own site's icon (or the emoji it was given), whichever page it's on, with the icon of a link
/// open in Peek from it in the corner.
struct FavoriteTile: View {
    let host: any SidebarHost
    let tab: Tab
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isChangingIcon = false

    var body: some View {
        Button {
            host.send(.tab(.select(tab.id)))
        } label: {
            TabIcon(tab: tab, size: 20, png: icon)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(alignment: .topTrailing) { peekBadge }
                .contentShape(Rectangle())
                .surface(host.state.selectedTabID == tab.id ? .selected : .resting, cornerRadius: 11)
        }
        .buttonStyle(.plain)
        .help(tab.displayTitle)
        .contextMenu {
            TabMenu(
                host: host, tab: tab,
                rename: {
                    newName = tab.displayTitle
                    isRenaming = true
                },
                changeIcon: { isChangingIcon = true })
        }
        .alert("Rename Favorite", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") { host.send(.tab(.rename(tab.id, title: newName))) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to show the page's own title.")
        }
        .popover(isPresented: $isChangingIcon, arrowEdge: .bottom) {
            TabIconPicker(current: tab.customIcon) { emoji in
                host.send(.tab(.setIcon(tab.id, emoji: emoji)))
                isChangingIcon = false
            }
        }
        .accessibilityIdentifier("sidebar.favorite")
    }

    /// The Favorite's own site's icon: the live page's while it's on that site, the cached one while it's elsewhere.
    private var icon: Data? {
        guard let home = tab.homeURL, let current = tab.url, home.host() != current.host() else { return host.favicon(for: tab) }
        return host.favicon(forURL: home) ?? host.favicon(for: tab)
    }

    @ViewBuilder private var peekBadge: some View {
        if let peek = host.peekOpened(from: tab.id) {
            SiteIcon(url: peek.url, size: 11, png: peek.png)
                .background(Circle().fill(.white).padding(-2))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(x: -3, y: 3)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Open in Peek")
        }
    }
}

/// A tab's icon: the emoji it was given, or its site's icon.
struct TabIcon: View {
    let tab: Tab
    let size: CGFloat
    let png: Data?

    var body: some View {
        if let emoji = tab.customIcon, !emoji.isEmpty {
            Text(emoji).font(.system(size: size)).frame(width: size + 4, height: size + 4).accessibilityHidden(true)
        } else {
            SiteIcon(url: tab.homeURL ?? tab.url, size: size, png: png)
        }
    }
}

/// Change Icon: an emoji for a tab, picked from a few or typed, or back to the site's icon.
struct TabIconPicker: View {
    let current: String?
    let pick: (String?) -> Void
    @State private var typed = ""

    static let choices = [
        "⭐️", "❤️", "🔥", "✅", "📌", "🚀", "💼", "📚", "🎵", "🎬", "📰", "💬",
        "🛒", "💰", "📈", "🧠", "🎨", "🏠", "✈️", "🍔", "⚽️", "🎮", "🔒", "🌍",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), spacing: 4) {
                ForEach(Self.choices, id: \.self) { emoji in
                    Button {
                        pick(emoji)
                    } label: {
                        Text(emoji).font(.system(size: 18)).frame(width: 30, height: 30)
                            .background(
                                current == emoji ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                }
            }
            TextField("Or type an emoji", text: $typed)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !typed.isEmpty { pick(typed) } }
            Button("Use the Site's Icon") { pick(nil) }
                .disabled(current == nil)
        }
        .padding(14)
        .frame(width: 290)
    }
}
