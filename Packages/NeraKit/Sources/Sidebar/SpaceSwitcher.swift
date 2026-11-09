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
                .contextMenu { SpaceMenuItems(host: host, space: space) }
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
