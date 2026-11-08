// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import CommandBar
import DesignSystem
import EngineKit
public import PageLifecycle
import SecurityPolicy
import Sidebar
public import SwiftUI
import UniformTypeIdentifiers

/// Top-level window content shared by macOS, iPadOS and iOS.
public struct RootView: View {
    @Bindable var model: AppModel
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    /// Creates the window content.
    public init(model: AppModel) {
        self.model = model
    }

    /// The window content.
    public var body: some View {
        layout
            .accessibilityHidden(model.isCommandBarPresented)  // the command bar is modal (A11Y-003)
            .focusedSceneValue(\.neraModel, model)
            .preferredColorScheme(colorScheme)
            .background(
                Theme.background(for: model.displayedTheme).animation(.easeInOut(duration: 0.45), value: model.state.selectedSpaceID)
            )
            .overlay {
                if model.isWelcomePresented {
                    WelcomeView(model: model)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 1.06))))
                }
            }
            .animation(.easeInOut(duration: 0.55), value: model.isWelcomePresented)
            .sheet(isPresented: isEditingSpace) {
                if let id = model.editingSpaceID { EditSpaceView(model: model, spaceID: id) }
            }
            .overlay {
                if model.isCommandBarPresented {
                    CommandBarView(host: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .overlay(alignment: .bottom) { if !model.isWelcomePresented { NoticeBanner(model: model) } }
            .animation(.snappy(duration: 0.18), value: model.isCommandBarPresented)
            .sheet(isPresented: $model.isHistoryPresented) { HistoryView(model: model) }
            .sheet(isPresented: $model.isClearDataPresented) { ClearBrowsingDataView(model: model) }
            .alert("Turn on developer tools?", isPresented: $model.isConfirmingDevTools) {
                Button("Turn On and Open") {
                    model.setDeveloperTools(true)
                    model.showDevTools()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Developer tools let you inspect and change pages. Turn them off any time in Settings › Advanced.")
            }
            .sheet(isPresented: $model.isBookmarksPresented) { BookmarksView(model: model) }
            #if os(macOS)
                .sheet(isPresented: $model.isBrowserImportPresented) { BrowserImportView(model: model) }
            #endif
            .fileImporter(isPresented: $model.isImportingFromArc, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { model.importArcSidebar(from: url) }
            }
            #if os(macOS)
                // Little Windows are opened here: the model asks, the window's environment opens them.
                .onChange(of: model.pendingLittleWindow, initial: true) { _, id in
                    guard let id else { return }
                    model.pendingLittleWindow = nil
                    openWindow(id: AppModel.littleWindowID, value: id)
                }
            #endif
    }

    /// Private windows are dark; otherwise the Space's light/dark choice, or the system's.
    private var colorScheme: ColorScheme? {
        if model.isPrivate { return .dark }
        switch model.state.selectedSpace?.theme.appearance {
        case .light?: return .light
        case .dark?: return .dark
        default: return nil
        }
    }

    /// The margin between the page and the window's edges.
    static let pageInset: CGFloat = 10
    /// The page's corner radius.
    static let pageRadius: CGFloat = 12

    private var isEditingSpace: Binding<Bool> {
        Binding(get: { model.editingSpaceID != nil }, set: { if !$0, model.editingSpaceID != nil { model.endEditingSpace(keep: true) } })
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if model.isPrivate { PrivateBadge() }
            SidebarView(
                host: model, accessory: AnyView(SidebarAccessories(model: model)),
                siteInfo: { AnyView(SiteInfoView(model: model)) }, nowPlaying: AnyView(MiniPlayer(model: model))
            )
        }
    }

    #if os(macOS)
        /// With the sidebar hidden, resting the pointer on the window's left edge slides it in over the page;
        /// it slides away when the pointer leaves it.
        @ViewBuilder private var peekingSidebar: some View {
            if model.isSidebarPeeking {
                sidebar
                    .frame(width: 260)
                    .padding(.top, 4)
                    .background(Theme.background(for: model.state.selectedSpace?.theme))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.28), radius: 24, x: 6)
                    .padding(.vertical, 6).padding(.leading, 6)
                    .onHover { inside in if !inside { model.isSidebarPeeking = false } }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                Color.clear.frame(width: 6).contentShape(Rectangle())
                    .onHover { inside in if inside { model.isSidebarPeeking = true } }
                    .padding(.top, 40)
            }
        }
    #endif

    @ViewBuilder private var layout: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                if model.isSidebarVisible {
                    sidebar
                        .frame(width: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if !model.isSidebarVisible { CollapsedTopBar(model: model).transition(.move(edge: .top).combined(with: .opacity)) }
                    ContentArea(model: model)
                        // During a back/forward swipe the page stays put; an arrow slides in over its edge.
                        .overlay(alignment: model.pageSwipeProgress < 0 ? .leading : .trailing) {
                            if model.pageSwipeProgress != 0 { SwipeArrow(progress: model.pageSwipeProgress) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Self.pageRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Self.pageRadius, style: .continuous).strokeBorder(.black.opacity(0.06)))
                        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                }
                .padding(.top, model.isSidebarVisible ? Self.pageInset : 0).padding(.bottom, Self.pageInset)
                .padding(.trailing, Self.pageInset)
                .padding(.leading, model.isSidebarVisible ? 0 : Self.pageInset)
            }
            .overlay(alignment: .leading) { if !model.isSidebarVisible { peekingSidebar } }
            // Every empty strip of the window (around the page, beside the window's buttons) acts as a title bar:
            // drag to move, double-click to zoom. Swipes are watched without taking any clicks.
            .background {
                ZStack {
                    TitleBarArea()
                    SwipeNavigation(model: model, sidebarWidth: model.isSidebarVisible ? 260 : nil)
                }
            }
            .ignoresSafeArea(.container, edges: .top)  // the sidebar runs up beside the window buttons, like the title bar
            .animation(.spring(response: 0.36, dampingFraction: 0.88), value: model.isSidebarVisible)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.isSidebarPeeking)
        #else
            NavigationSplitView {
                SidebarView(
                    host: model, accessory: AnyView(SidebarAccessories(model: model)),
                    siteInfo: { AnyView(SiteInfoView(model: model)) })
            } detail: {
                ContentArea(model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
        #endif
    }
}

/// The web content region. Page requests (dialogs, permissions…) are drawn **inside** this region,
/// never over browser chrome, so a page can't make its prompts look like browser UI.
struct ContentArea: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            let panes = model.splitPanes
            if model.selectedTabCrashed {
                SadTabView { model.reloadCrashedTab() }
            } else if panes.count > 1, let split = model.state.selectedSplit {
                SplitViewContent(model: model, panes: panes, axis: split.axis)
            } else if let page = model.selectedPage {
                VStack(spacing: 0) {
                    PageProgressBar(page: page)
                    WebViewHost(page: page, isAccessible: model.currentRequest == nil && model.currentDangerousSite == nil)
                        .overlay { DangerousSiteOverlay(model: model, pageID: page.id) }
                        .id(page.id)
                        .accessibilityHidden(model.currentRequest != nil)
                }
            } else {
                StartPage(model: model)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isFindBarPresented, model.selectedPage != nil, model.currentRequest == nil { FindBar(model: model) }
        }
        .overlay(alignment: .topTrailing) {
            if model.isSiteStyleEditorPresented, let page = model.selectedPage, let site = SiteStyle.site(of: page.state.url) {
                SiteStyleEditor(model: model, page: page, site: site)
                    .id(site)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.isSiteStyleEditorPresented)
        .overlay(alignment: .top) {
            if let zoom = model.zoomIndicator { ZoomIndicator(factor: zoom).transition(.opacity) }
        }
        .overlay(alignment: .top) {
            if model.assistive.restartSuggested {
                AssistiveRestartBanner(model: model)
            } else if let site = model.mediaSuggestion, model.currentRequest == nil {
                MediaSuggestionBanner(model: model, site: site)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.assistive.restartSuggested)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.mediaSuggestion)
        .overlay {
            // A failed load (not when the engine already asks about the certificate itself).
            if model.currentDangerousSite == nil, let failure = model.currentLoadFailure, !model.isAskingAboutCertificate {
                PageErrorView(model: model, failure: failure)
            }
        }
        .overlay {
            if let request = model.currentRequest {
                PageRequestView(request: request, model: model)
                    .id(request.id)
            }
        }
        .overlay {
            if let page = model.peekPage {
                PeekView(model: model, page: page)
                    .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.peek)
        .onChange(of: model.state.selectedTabID) { _, _ in
            if model.isFindBarPresented { model.hideFindBar() }
            if model.isZapping { model.isZapping = false }
            model.isSiteStyleEditorPresented = false
        }
    }
}

struct PageProgressBar: View {
    let page: any WebPage

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * page.state.progress)
                .opacity(page.state.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: page.state.progress)
        }
        .frame(height: 2)
    }
}

/// Shown when a page's content process exited.
struct SadTabView: View {
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("This page stopped working").font(.title3.weight(.medium))
            Text("Your tabs and other pages are fine.").foregroundStyle(.secondary)
            Button("Reload", action: reload)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("sadTab.reload")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityIdentifier("sadTab")
    }
}

struct NoticeBanner: View {
    @Bindable var model: AppModel

    private var download: DownloadItem? {
        model.pages.downloads.last { item in
            switch item.state {
            case .finished?, .failed?: true
            default: false
            }
        }
    }

    var body: some View {
        if case .ready(let version) = model.updateStatus, !model.isUpdateBannerDismissed {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nera \(version) is ready").lineLimit(1)
                    Text("It installs when you quit, or now.").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                #if os(macOS)
                    Button("Restart to Update") { model.restartToUpdate() }.accessibilityIdentifier("update.restart")
                #endif
                Button("Later") { model.isUpdateBannerDismissed = true }.buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(16)
            .frame(maxWidth: 560)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("update.ready")
        } else if let update = model.availableUpdate {
            HStack {
                Image(systemName: "arrow.down.app.fill").foregroundStyle(.tint)
                Text("Nera \(update.version) is available.").lineLimit(1)
                Spacer(minLength: 8)
                Button("Download") { model.downloadUpdate() }.accessibilityIdentifier("update.download")
                Button("Later") { model.availableUpdate = nil }.buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(16)
            .frame(maxWidth: 560)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("update.banner")
        } else if let text = model.notice ?? model.pages.lastBlocked.map({ "Blocked: \($0.reason.rawValue)" }) {
            banner(text, icon: model.notice == nil ? "hand.raised.fill" : "checkmark.circle.fill") {
                model.notice = nil
                model.pages.lastBlocked = nil
            }
        } else if !model.isSidebarVisible, let download {  // with the sidebar shown, the Downloads button reports it
            let text: String = {
                if case .failed(let why)? = download.state { return "Download failed: \(download.filename) (\(why))" }
                return "Downloaded \(download.filename)"
            }()
            banner(text, icon: "arrow.down.circle.fill") { model.pages.dismissDownload(download.id) }
        }
    }

    private func banner(_ text: String, icon: String, dismiss: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text).lineLimit(2)
            Spacer(minLength: 8)
            Button("Dismiss", action: dismiss).buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(16)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notice.banner")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "Private" at the top of a private window's sidebar.
struct PrivateBadge: View {
    var body: some View {
        Label("Private", systemImage: "eyeglasses")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10).padding(.top, 10)
            .help("Private window: no history, and cookies and site data are deleted when it closes")
            .accessibilityIdentifier("private.badge")
    }
}

/// A private window (⇧⌘N): its own memory-only model and session, ended when the window closes.
public struct PrivateWindowRoot: View {
    @State private var model: AppModel

    /// Creates a private window sharing the main window's engines.
    public init(registry: EngineRegistry) {
        _model = State(initialValue: AppModel.privateWindow(registry: registry))
    }

    /// The window content.
    public var body: some View {
        RootView(model: model)
            .onDisappear { model.closePrivateWindow() }
    }
}

/// The sidebar's bottom-bar buttons: Extensions (macOS) and Downloads.
struct SidebarAccessories: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            #if os(macOS)
                ExtensionsButton(model: model)
            #endif
            DownloadsButton(model: model)
        }
    }
}

#if os(macOS)
    /// The slim bar above the page while the sidebar is hidden: room for the window's buttons, the sidebar
    /// toggle, back/forward/reload, and the page's address (click to edit).
    struct CollapsedTopBar: View {
        @Bindable var model: AppModel

        var body: some View {
            let nav = model.pageNavigation
            ZStack {
                TitleBarArea()  // drag to move, double-click to zoom, like a title bar
                HStack(spacing: 2) {
                    SidebarIconButton(symbol: "sidebar.left", help: "Show Sidebar (⌘S)") { model.toggleSidebar() }
                    SidebarIconButton(symbol: "arrow.left", help: "Back (⌘[)", isEnabled: nav.canGoBack) { model.goBack() }
                    SidebarIconButton(symbol: "arrow.right", help: "Forward (⌘])", isEnabled: nav.canGoForward) { model.goForward() }
                    SidebarIconButton(
                        symbol: nav.isLoading ? "xmark" : "arrow.clockwise", help: "Reload (⌘R)", isEnabled: model.state.selectedTab != nil
                    ) { model.reload() }
                    Spacer()
                }
                .padding(.leading, 74)  // the window's buttons sit here
                addressPill
            }
            .padding(.trailing, 8)
            .frame(height: 30)  // centered on the window buttons
            .padding(.bottom, 6)
        }

        /// The page's icon and address, centered on the window; click to edit (⌘L).
        private var addressPill: some View {
            let tab = model.state.selectedTab
            return Button {
                model.showCommandBar(.currentTab)
            } label: {
                HStack(spacing: 7) {
                    if let tab, tab.url != nil {
                        SiteIcon(url: tab.url, size: 12, png: model.favicon(for: tab))
                    } else {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Text(tab?.url.map { DisplayURL.short($0) } ?? "Search or enter address")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(minWidth: 300, maxWidth: 460, minHeight: 26)
                .surface(.resting, cornerRadius: 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit the address (⌘L)")
            .accessibilityLabel("Address")
            .accessibilityValue(tab?.url?.absoluteString ?? "")
        }
    }
#endif
