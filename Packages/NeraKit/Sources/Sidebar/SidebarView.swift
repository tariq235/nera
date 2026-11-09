// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
public import SwiftUI

/// The vertical sidebar: address pill, Favorites, pinned and Today sections, Space switcher.
public struct SidebarView: View {
    let host: any SidebarHost
    let accessory: AnyView
    let siteInfo: (() -> AnyView)?
    let nowPlaying: AnyView

    /// Creates the sidebar for a host (normally the app model).
    /// - Parameters:
    ///   - host: The app model.
    ///   - accessory: Sits in the bottom bar, next to the Space switcher's "+" menu (the Downloads button).
    ///   - siteInfo: Content of the popover behind the address pill's site button (connection and permissions).
    ///   - nowPlaying: Sits above the bottom bar (the mini player of a tab playing in the background).
    public init(
        host: any SidebarHost, accessory: AnyView = AnyView(EmptyView()), siteInfo: (() -> AnyView)? = nil,
        nowPlaying: AnyView = AnyView(EmptyView())
    ) {
        self.host = host
        self.accessory = accessory
        self.siteInfo = siteInfo
        self.nowPlaying = nowPlaying
    }

    private var space: Space? { host.state.selectedSpace }

    /// The sidebar.
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarTopBar(host: host)
            AddressPill(host: host, siteInfo: siteInfo)
            if !host.isPrivateSession { FavoritesGrid(host: host) }
            // The Spaces sit side by side and slide as one: a two-finger swipe drags them with the fingers, and
            // switching Space glides to the next one. Only the visible Space takes clicks.
            GeometryReader { geo in
                let width = geo.size.width
                let spaces = host.state.spaces
                let index = CGFloat(spaces.firstIndex { $0.id == host.state.selectedSpaceID } ?? 0)
                HStack(alignment: .top, spacing: Self.pageGap) {
                    ForEach(spaces) { space in
                        let isCurrent = space.id == host.state.selectedSpaceID
                        spaceContent(space)
                            .frame(width: width)
                            .allowsHitTesting(isCurrent)
                            .accessibilityHidden(!isCurrent)
                    }
                }
                .offset(x: -index * (width + Self.pageGap) + host.spaceSwipeOffset)
                .animation(.spring(response: 0.44, dampingFraction: 0.9), value: index)
            }
            .clipped()
            // Keyboard (A11Y-004): ↑/↓ move between tabs, Return goes into the page, Space opens or closes the
            // selected tab's folder. Reached with Tab when "Keyboard navigation" is on in System Settings.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1) }
            .onKeyPress(.upArrow) { step(-1) }
            .onKeyPress(.return) {
                host.focusPage()
                return .handled
            }
            .onKeyPress(.space) {
                guard let tab = host.state.selectedTabID, let folder = host.state.folderID(containing: tab) else { return .ignored }
                host.send(.space(.toggleFolder(folder)))
                return .handled
            }
            .accessibilityLabel("Tabs")
            .accessibilityHint("Use the up and down arrow keys to move between tabs.")
            nowPlaying
            SpaceSwitcher(host: host, accessory: accessory)
        }
        .padding(.horizontal, 10)
        .padding(.top, 1)  // lines the top bar up with the window's buttons
        .padding(.bottom, 8)
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        host.send(.tab(.selectAdjacent(offset: offset)))
        return .handled
    }

    /// Space between neighboring Spaces while they slide.
    static let pageGap: CGFloat = 24

    private func spaceContent(_ space: Space) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if host.isPrivateSession {
                Text("Private Tabs").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sidebar.privateTabs")
            } else {
                SpaceHeader(host: host, space: space)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(space.pinned) { node in NodeRow(host: host, node: node).sidebarDropTarget(host, .before(node.id)) }
                    if !host.isPrivateSession {
                        TodayDivider(host: host).sidebarDropTarget(host, .endOf(.pinned))  // drop on the divider to pin
                    }
                    NewTabRow(host: host)
                    ForEach(space.today) { node in NodeRow(host: host, node: node).sidebarDropTarget(host, .before(node.id)) }
                    // The empty area below Today: drop to put an item at the end of Today (or a link to open it).
                    Color.clear.frame(height: 60).contentShape(Rectangle()).sidebarDropTarget(host, .endOf(.today))
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Right-click anywhere in the Space that isn't a tab or folder (those have their own menus).
        .contextMenu { if !host.isPrivateSession { SpaceMenuItems(host: host, space: space) } }
    }
}

/// The Space's menu (right-click the Space, its header's "…" or its icon): its look, its profile, a folder, delete.
struct SpaceMenuItems: View {
    let host: any SidebarHost
    let space: Space

    var body: some View {
        Button("Change Space Icon…") { host.editSpace(space.id) }
        Button("Rename Space…") { host.editSpace(space.id) }
        Button("Edit Theme Color…") { host.editSpace(space.id) }
        if host.state.profiles.count > 1 {
            Menu("Set Profile") {
                ForEach(host.state.profiles) { profile in
                    Toggle(
                        profile.name,
                        isOn: Binding(
                            get: { space.profileID == profile.id },
                            set: { if $0 { host.send(.space(.setProfile(space.id, profileID: profile.id))) } }))
                }
            }
        }
        Divider()
        Button("New Folder") { host.send(.space(.createFolder(title: "New Folder"))) }
        if !space.today.isEmpty { Button("Clear Today Tabs") { host.send(.space(.clearToday)) } }
        if host.state.spaces.count > 1 {
            Divider()
            Button("Delete Space", role: .destructive) { host.send(.space(.delete(space.id))) }
        }
    }
}

/// The row beside the window's close/minimize/zoom buttons: sidebar toggle, back, forward, reload.
struct SidebarTopBar: View {
    let host: any SidebarHost

    var body: some View {
        let nav = host.pageNavigation
        HStack(spacing: 2) {
            SidebarIconButton(symbol: "sidebar.left", help: "Hide Sidebar (⌘S)") { host.toggleSidebar() }
            Spacer(minLength: 4)
            SidebarIconButton(symbol: "arrow.left", help: "Back (⌘[)", isEnabled: nav.canGoBack) { host.goBack() }
                .accessibilityIdentifier("sidebar.back")
            SidebarIconButton(symbol: "arrow.right", help: "Forward (⌘])", isEnabled: nav.canGoForward) { host.goForward() }
                .accessibilityIdentifier("sidebar.forward")
            SidebarIconButton(
                symbol: nav.isLoading ? "xmark" : "arrow.clockwise", help: "Reload (⌘R)", isEnabled: host.state.selectedTab != nil
            ) {
                host.reload()
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityIdentifier("sidebar.reload")
        }
        .frame(height: 28)
        .padding(.leading, 66)  // the window's buttons sit here
        #if os(macOS)
            .background(TitleBarArea())  // drag to move, double-click to zoom, like a title bar
        #endif
    }
}

/// A small borderless icon button with a hover fill.
public struct SidebarIconButton: View {
    let symbol: String
    let help: String
    var isEnabled = true
    let action: () -> Void
    @State private var isHovering = false

    /// Creates the button.
    public init(symbol: String, help: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.isEnabled = isEnabled
        self.action = action
    }

    /// The button.
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
                .surface(isHovering && isEnabled ? .hover : nil, cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(isEnabled ? 0.7 : 0.25))
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The Space's name above its pinned tabs, with its menu.
struct SpaceHeader: View {
    let host: any SidebarHost
    let space: Space
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            SpaceIconView(icon: space.icon).frame(width: 16)
            Text(space.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer()
            Menu {
                SpaceMenuItems(host: host, space: space)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovering ? 1 : 0.45)
            .accessibilityLabel("Space options")
            .accessibilityIdentifier("sidebar.spaceMenu")
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 8).padding(.top, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { host.editSpace(space.id) }
        .accessibilityIdentifier("sidebar.spaceHeader")
    }
}

/// "+ New Tab" between pinned and Today.
struct NewTabRow: View {
    let host: any SidebarHost
    @State private var isHovering = false

    var body: some View {
        Button {
            host.showCommandBar(.newTab)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 18)
                Text("New Tab")
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
            .surface(isHovering ? .hover : nil)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.6))
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("sidebar.newTab")
    }
}

struct AddressPill: View {
    let host: any SidebarHost
    var siteInfo: (() -> AnyView)?
    @State private var isSiteInfoPresented = false

    private var isWebPage: Bool {
        guard let scheme = host.state.selectedTab?.url?.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    var body: some View {
        HStack(spacing: 0) {
            if let siteInfo, isWebPage {
                let insecure = DisplayURL.isInsecure(host.state.selectedTab?.url)
                Button {
                    isSiteInfoPresented.toggle()
                } label: {
                    Image(systemName: insecure ? "exclamationmark.triangle.fill" : "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(insecure ? Color.orange : Color.primary.opacity(0.55))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(insecure ? "Not secure: this page doesn't use HTTPS. Site settings" : "Connection is secure. Site settings")
                .accessibilityLabel(insecure ? "Not secure. Site settings" : "Site settings")
                .accessibilityIdentifier("sidebar.siteInfo")
                .popover(isPresented: $isSiteInfoPresented, arrowEdge: .bottom) { siteInfo() }
            }
            urlButton
        }
        .surface(.resting, cornerRadius: 10)
    }

    private var urlButton: some View {
        Button {
            host.showCommandBar(.currentTab)
        } label: {
            HStack(spacing: 6) {
                if siteInfo == nil, DisplayURL.isInsecure(host.state.selectedTab?.url) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Not secure: this page doesn't use HTTPS")
                }
                let text = DisplayURL.short(host.state.selectedTab?.url)
                if text.isEmpty {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(text.isEmpty ? "Search or enter URL" : text)
                    .lineLimit(1)
                    .foregroundStyle(host.state.selectedTab == nil ? .secondary : .primary)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.leading, isWebPage && siteInfo != nil ? 0 : 10).padding(.trailing, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.address")
    }
}

struct FavoritesGrid: View {
    let host: any SidebarHost

    var body: some View {
        let favorites = host.state.currentProfile?.favorites ?? []
        if !favorites.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(favorites) { tab in
                    Button {
                        host.send(.tab(.select(tab.id)))
                    } label: {
                        SiteIcon(url: tab.url, size: 20, png: host.favicon(for: tab))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                            .surface(host.state.selectedTabID == tab.id ? .selected : .resting, cornerRadius: 11)
                    }
                    .buttonStyle(.plain)
                    .help(tab.displayTitle)
                    .contextMenu { TabMenu(host: host, tab: tab) }
                }
            }
            .dropDestination(for: String.self) { items, _ in handleSidebarDrop(items, on: host, to: .favorites) }
        }
    }
}

struct NodeRow: View {
    let host: any SidebarHost
    let node: Node
    @State private var isRenaming = false
    @State private var newFolderName = ""

    var body: some View {
        switch node.kind {
        case .tab(let tab):
            TabRow(host: host, tab: tab)
        case .folder(let folder):
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    host.send(.space(.toggleFolder(node.id)))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 13)).foregroundStyle(.primary.opacity(0.6)).frame(width: 18)
                        Text(folder.title).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename Folder…") {
                        newFolderName = folder.title
                        isRenaming = true
                    }
                    Button("Delete Folder (Keep Tabs)") { host.send(.space(.deleteFolder(node.id))) }
                }
                .alert("Rename Folder", isPresented: $isRenaming) {
                    TextField("Name", text: $newFolderName)
                    Button("Rename") { host.send(.space(.renameFolder(node.id, title: newFolderName))) }
                    Button("Cancel", role: .cancel) {}
                }
                .draggable(node.id.uuidString)
                .dropDestination(for: String.self) { items, _ in handleSidebarDrop(items, on: host, to: .intoFolder(node.id)) }
                if folder.isExpanded {
                    ForEach(folder.children) { child in
                        NodeRow(host: host, node: child).padding(.leading, 14).sidebarDropTarget(host, .before(child.id))
                    }
                }
            }
        case .split(let split):
            VStack(spacing: 0) {
                ForEach(split.tabs) { tab in TabRow(host: host, tab: tab) }
            }
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                // The bar on the left drags the whole split; each row drags just its tab.
                RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.18)).frame(width: 4).padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .draggable(node.id.uuidString)
                    .help("Drag to move the Split View")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
        }
    }
}

struct TabRow: View {
    let host: any SidebarHost
    let tab: Tab
    @State private var isHovering = false

    private var isSelected: Bool { host.state.selectedTabID == tab.id }

    var body: some View {
        HStack(spacing: 8) {
            SiteIcon(url: tab.url, size: 14, png: host.favicon(for: tab))
            Text(tab.displayTitle).lineLimit(1)
                .fontWeight(isSelected ? .medium : .regular)
            Spacer(minLength: 4)
            if isHovering || isSelected {
                Button {
                    host.send(.tab(.close(tab.id)))
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(tab.displayTitle)")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 7)
        .surface(isSelected ? .selected : (isHovering ? .hover : nil))
        .contentShape(Rectangle())
        .onTapGesture { host.send(.tab(.select(tab.id))) }
        .onHover { isHovering = $0 }
        .contextMenu { TabMenu(host: host, tab: tab) }
        .draggable(tab.id.uuidString)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar.tab")
        .accessibilityLabel(tab.displayTitle)
    }
}

struct TabMenu: View {
    let host: any SidebarHost
    let tab: Tab

    var body: some View {
        let location = host.state.locate(tab.id)?.location
        let isPinned: Bool = {
            if case .space(_, .pinned)? = location { return true }
            if case .favorite? = location { return true }
            return false
        }()
        let isFavorite: Bool = {
            if case .favorite? = location { return true }
            return false
        }()
        Button(isPinned ? "Unpin" : "Pin") { host.send(.tab(.togglePin(tab.id))) }
        if case .favorite? = location {
        } else {
            Button("Add to Favorites") { host.send(.tab(.addToFavorites(tab.id))) }
        }
        if tab.homeURL != nil, tab.homeURL != tab.url {
            Button("Reset to Original URL") { host.send(.tab(.resetToHome(tab.id))) }
        }
        Divider()
        if let selected = host.state.selectedTabID, selected != tab.id, !isFavorite {
            Button("Split View with Current Tab") { host.send(.tab(.splitWith(selected, other: tab.id))) }
        }
        if host.state.selectedSpace.map({ ($0.pinned + $0.today).split(containing: tab.id) != nil }) == true {
            Button("Remove from Split View") { host.send(.tab(.removeFromSplit(tab.id))) }
        }
        Divider()
        Button("Copy URL") { Clipboard.copy(tab.url?.absoluteString ?? "") }
        Divider()
        Button(isPinned ? "Unload" : "Close", role: .destructive) { host.send(.tab(.close(tab.id))) }
    }
}

struct TodayDivider: View {
    let host: any SidebarHost

    var body: some View {
        HStack {
            Rectangle().fill(.primary.opacity(0.12)).frame(height: 1)
            if !(host.state.selectedSpace?.today.isEmpty ?? true) {
                Button("Clear") { host.send(.space(.clearToday)) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sidebar.clearToday")
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Drag and drop

/// Handles strings dropped on the sidebar: a dragged sidebar item (its ID) moves; a web link opens as a new tab.
@MainActor
func handleSidebarDrop(_ items: [String], on host: any SidebarHost, to destination: NodeDestination) -> Bool {
    var handled = false
    for item in items {
        if let id = UUID(uuidString: item) {
            host.send(.tab(.moveNode(id, to: destination)))
            handled = true
        } else if let url = URL(string: item.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        {
            host.send(.tab(.open(url, .newTab)))  // the engine still applies the navigation policy
            handled = true
        }
    }
    return handled
}

/// A drop target with an insertion line when something is dragged over it.
struct DropTarget: ViewModifier {
    let host: any SidebarHost
    let destination: NodeDestination
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isTargeted { Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 4).allowsHitTesting(false) }
            }
            .dropDestination(for: String.self) { items, _ in
                handleSidebarDrop(items, on: host, to: destination)
            } isTargeted: {
                isTargeted = $0
            }
    }
}

extension View {
    func sidebarDropTarget(_ host: any SidebarHost, _ destination: NodeDestination) -> some View {
        modifier(DropTarget(host: host, destination: destination))
    }
}
