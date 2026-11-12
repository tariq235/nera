// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import SwiftUI

struct SpaceSwitcher: View {
    let host: any SidebarHost
    var accessory = AnyView(EmptyView())

    /// "Work" or, with several profiles, "Work · Work profile".
    private func spaceHelp(_ space: Space) -> String {
        guard host.state.profiles.count > 1, let profile = host.state.profiles.first(where: { $0.id == space.profileID }),
            profile.name != space.title
        else { return space.title }
        return "\(space.title) · \(profile.name)"
    }

    var body: some View {
        if host.isPrivateSession {
            // A private window has one list of tabs: no Spaces to switch or create.
            HStack(spacing: 4) {
                Spacer()
                accessory
                Button {
                    host.showCommandBar(.newTab)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Tab (⌘T)")
                .accessibilityLabel("New Tab")
            }
            .padding(.horizontal, 4)
        } else {
            spaces
        }
    }

    private var spaces: some View {
        HStack(spacing: 4) {
            ForEach(host.state.spaces) { space in
                Button {
                    host.send(.space(.select(space.id)))
                } label: {
                    let isSelected = space.id == host.state.selectedSpaceID
                    SpaceIconView(icon: space.icon)
                        .foregroundStyle(.primary.opacity(isSelected ? 0.85 : 0.4))
                        .frame(width: 28, height: 26)
                        .surface(isSelected ? .selected : nil, cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help(spaceHelp(space))
                .accessibilityLabel(spaceHelp(space))
                .accessibilityIdentifier("sidebar.space")
                .contextMenu { SpaceMenuItems(host: host, space: space) }
                .draggable(SpaceDrag.payload(space.id))
                .dropDestination(for: String.self) { items, _ in SpaceDrag.drop(items, on: space.id, host: host) }
            }
            Spacer()
            accessory
            Menu {
                Button("New Space…") { host.newSpace() }
                Button("New Folder") { host.send(.space(.createFolder(title: "New Folder"))) }
                Divider()
                Button("Import from Arc…") { host.requestArcImport() }  // naming: import-reference
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("New Space, folder or import")
            .accessibilityLabel("New Space, folder or import")
            .accessibilityIdentifier("sidebar.plusMenu")
        }
    }
}

/// Dragging in the bottom bar: a Space's icon onto another moves it there; a tab onto a Space's icon moves the tab
/// to that Space, as in Arc.
enum SpaceDrag {
    private static let prefix = "space:"

    /// What a Space's icon carries when dragged (a tab carries its bare ID).
    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    @MainActor
    static func drop(_ items: [String], on target: UUID, host: any SidebarHost) -> Bool {
        var handled = false
        for item in items {
            if item.hasPrefix(prefix), let id = UUID(uuidString: String(item.dropFirst(prefix.count))) {
                host.send(.space(.move(id, before: target)))
                handled = true
            } else if let id = UUID(uuidString: item) {
                host.send(.tab(.moveToSpace(id, spaceID: target)))
                handled = true
            }
        }
        return handled
    }
}
