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
        /// Follows `model.isSidebarVisible` with an animation: whether the sidebar is on screen.
        @State private var sidebarShown = true
        /// Whether the page has its narrow size beside the sidebar (set once the sidebar has slid in).
        @State private var pageBesideSidebar = true
        /// The sidebar's width, set by dragging its edge; kept per Mac, like other window layout.
        @AppStorage("sidebarWidth") private var storedSidebarWidth = Double(Self.defaultSidebarWidth)
        /// The width when a drag on the sidebar's edge began.
        @State private var dragStartWidth: CGFloat?

        private var sidebarWidth: CGFloat { min(max(storedSidebarWidth, Self.sidebarWidths.lowerBound), Self.sidebarWidths.upperBound) }
    #endif

    /// Creates the window content.
    public init(model: AppModel) {
        self.model = model
    }

    /// The window content.
    public var body: some View {
        layout
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
                    CommandBarView(host: model, leadingInset: commandBarInset)  // appears at once, like a menu
                }
            }
            .overlay(alignment: .bottom) { if !model.isWelcomePresented { NoticeBanner(model: model) } }
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

    /// The command bar is centered over the page, beside the sidebar when it's shown.
    private var commandBarInset: CGFloat {
        #if os(macOS)
            sidebarShown ? sidebarWidth : 0
        #else
            0
        #endif
    }

    /// Light or dark (Settings › General › Appearance; private windows are always dark).
    private var colorScheme: ColorScheme? { model.preferredColorScheme }

    /// The margin between the page and the window's edges.
    static let pageInset: CGFloat = 10
    /// The page's corner radius.
    static let pageRadius: CGFloat = 12
    /// The sidebar's width range when dragging its edge, and its width until then.
    static let sidebarWidths: ClosedRange<CGFloat> = 200...420
    static let defaultSidebarWidth: CGFloat = 260
    /// Showing and hiding the sidebar: one motion for the sidebar and the page, without overshoot (a bounce would
    /// open a gap beside the page).
    static let sidebarMotion = Animation.spring(response: 0.25, dampingFraction: 1)

    private var isEditingSpace: Binding<Bool> {
        Binding(get: { model.editingSpaceID != nil }, set: { if !$0, model.editingSpaceID != nil { model.endEditingSpace(keep: true) } })
    }

    #if os(macOS)
        /// The sidebar's edge: drag it to make the sidebar wider or narrower (the page follows as it goes).
        private var resizeHandle: some View {
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStartWidth ?? sidebarWidth
                            dragStartWidth = start
                            let width = min(
                                max(start + drag.translation.width, Self.sidebarWidths.lowerBound), Self.sidebarWidths.upperBound)
                            var still = Transaction()
                            still.disablesAnimations = true
                            withTransaction(still) { storedSidebarWidth = Double(width.rounded()) }
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
                .offset(x: sidebarWidth - 4)
                // VoiceOver and keyboard users get the same width as a slider.
                .accessibilityRepresentation {
                    Slider(
                        value: Binding(get: { Double(sidebarWidth) }, set: { storedSidebarWidth = $0.rounded() }),
                        in: Double(Self.sidebarWidths.lowerBound)...Double(Self.sidebarWidths.upperBound), step: 20
                    ) { Text("Sidebar width") }
                }
                .accessibilityIdentifier("sidebar.resizeHandle")
        }
    #endif

    private var sidebar: some View {
        VStack(spacing: 0) {
            SidebarView(
                host: model, accessory: AnyView(SidebarAccessories(model: model)),
                siteInfo: { AnyView(SiteInfoView(model: model)) },
                nowPlaying: AnyView(
                    VStack(spacing: 8) {
                        UpdateCard(model: model)
                        MiniPlayer(model: model)
                    })
            )
        }
    }

    #if os(macOS)
        /// With the sidebar hidden, resting the pointer on the window's left edge slides it in over the page;
        /// it slides away when the pointer leaves it.
        @ViewBuilder private var peekingSidebar: some View {
            if model.isSidebarPeeking {
                sidebar
                    .frame(width: sidebarWidth)
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
            }
        }
    #endif

    #if os(macOS)
        /// The page, with its rounded corners and shadow.
        private var page: some View {
            ContentArea(model: model)
                // During a back/forward swipe the page stays put; an arrow slides in over its edge.
                .overlay(alignment: model.pageSwipeProgress < 0 ? .leading : .trailing) {
                    if model.pageSwipeProgress != 0 { SwipeArrow(progress: model.pageSwipeProgress) }
                }
                .clipShape(RoundedRectangle(cornerRadius: isPageFullscreen ? 0 : Self.pageRadius, style: .continuous))
                .overlay {
                    if !isPageFullscreen {
                        RoundedRectangle(cornerRadius: Self.pageRadius, style: .continuous).strokeBorder(.black.opacity(0.06))
                    }
                }
                .shadow(color: .black.opacity(isPageFullscreen ? 0 : 0.14), radius: 6, y: 2)
        }

        /// The selected page is showing HTML full screen (a video's full-screen button): it fills the screen alone.
        private var isPageFullscreen: Bool {
            model.pages.fullscreenPageID != nil && model.pages.fullscreenPageID == model.state.selectedTabID
        }
    #endif

    @ViewBuilder private var layout: some View {
        #if os(macOS)
            // ⌘S: the sidebar and the page move as one. Showing it, the sidebar slides in from the left and pushes
            // the page over; hiding it, both slide left and the page fills the window inside a thin frame.
            // During the slide the page keeps its wide size (what passes the window's edge is clipped, so no gap
            // opens beside it) and is moved by an offset, which the GPU composites at full frame rate; it takes its
            // narrow size once the sidebar is in. So the engine lays the page out once per toggle, not per frame.
            ZStack(alignment: .leading) {
                page
                    .padding(.leading, isPageFullscreen ? 0 : pageBesideSidebar ? sidebarWidth : Self.pageInset)
                    .padding([.top, .bottom, .trailing], isPageFullscreen ? 0 : Self.pageInset)
                    .offset(x: sidebarShown && !pageBesideSidebar ? sidebarWidth - Self.pageInset : 0)
                    // Changing size or start position is never animated; only the slide is.
                    .transaction(value: pageBesideSidebar) { $0.animation = nil }
                // Always built, moved off-screen when hidden: showing it is then only a move, in the same motion as
                // the page (building it on ⌘S cost the first frames, so it appeared without sliding), and it keeps its
                // scroll position.
                sidebar
                    .frame(width: sidebarWidth)
                    .offset(x: sidebarShown && !isPageFullscreen ? 0 : -sidebarWidth)
                    .allowsHitTesting(sidebarShown)
                    .accessibilityHidden(!sidebarShown)
                if sidebarShown && pageBesideSidebar && !isPageFullscreen { resizeHandle }
            }
            .onChange(of: model.isSidebarVisible) { _, visible in
                if visible {
                    withAnimation(Self.sidebarMotion) {
                        sidebarShown = true
                    } completion: {
                        if model.isSidebarVisible { pageBesideSidebar = true }
                    }
                } else {
                    pageBesideSidebar = false  // wide, still where it was; then the slide
                    DispatchQueue.main.async { withAnimation(Self.sidebarMotion) { sidebarShown = false } }
                }
            }
            .onAppear {
                sidebarShown = model.isSidebarVisible
                pageBesideSidebar = model.isSidebarVisible
            }
            .overlay(alignment: .leading) { if !model.isSidebarVisible && !isPageFullscreen { peekingSidebar } }
            // Every empty strip of the window (around the page, beside the window's buttons) acts as a title bar:
            // drag to move, double-click to zoom. Swipes are watched without taking any clicks.
            .background {
                ZStack {
                    TitleBarArea()
                    SwipeNavigation(model: model, sidebarWidth: model.isSidebarVisible ? sidebarWidth : nil)
                    WindowButtons(visible: (sidebarShown || model.isSidebarPeeking) && !isPageFullscreen)
                    FullScreenWindow(isOn: isPageFullscreen) {
                        if let id = model.pages.fullscreenPageID { model.pages.existingPage(for: id)?.exitFullscreen() }
                    }
                    TabKeys(model: model)
                }
            }
            .ignoresSafeArea(.container, edges: .top)  // the sidebar runs up beside the window buttons, like the title bar
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
            } else if model.isPrivate {
                Rectangle().fill(.background)  // nothing kept, nothing suggested: an empty page
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
        // With the sidebar shown, updates are a card at its bottom (UpdateCard); hidden, a banner here.
        if !model.isSidebarVisible, case .ready(let version) = model.updateStatus, !model.isUpdateBannerDismissed {
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
        } else if !model.isSidebarVisible, let update = model.availableUpdate {
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
            .onAppear { model.showCommandBar(.newTab) }  // a new private window is for typing an address
            #if os(macOS)
                .background(MatchMainWindowFrame())
            #endif
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
