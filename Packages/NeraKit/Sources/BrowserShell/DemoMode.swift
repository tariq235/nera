// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// log-check: debug-only (prints progress; not compiled into Release)
// Debug-only demo library and self-screenshots for the README:
//   Nera --demo                         a throwaway in-memory library with Spaces, folders, Favorites and a split
//   Nera --demo --screenshot out.png    also visits every tab (so real site icons load), then saves the window
//   ... --size 1180x720                 window size for the shot (default 1440x900)
//   ... --quick                         don't visit every tab first (faster; placeholder icons)
//   ... --url <url>                     open this page first, in any scene (--webkit: with WebKit)
//   ... --hold <seconds>                wait before the shot (time to drive the window from a test script)
//   ... --frames <dir>                  with --shot retoggle: record the window during both animations
//   ... --shot <name>                    which scene: hero (default), command, start, split, editSpace, newSpace,
//                                        private (a private window), or a welcome step: welcome-intro, welcome-essentials, welcome-privacy,
//                                        welcome-source, welcome-spaces, welcome-extensions, welcome-favorites,
//                                        welcome-summary, welcome-theme (made-up import data, never the Mac's own)
// The app captures only its own window, which needs no Screen Recording permission.
#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import Foundation
    import Import
    import SwiftUI
    import BrowserData

    @MainActor
    enum DemoMode {
        static var isRequested: Bool { CommandLine.arguments.contains("--demo") }

        static func argument(after flag: String) -> String? {
            guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i + 1]
        }

        /// The demo library.
        static func library() -> BrowserState {
            if PromoMode.scene != nil { return PromoMode.library() }  // --promo: the promo video's sidebar
            let now = Date()
            func tab(_ url: String, _ title: String, home: Bool = false, ago: TimeInterval = 600) -> Tab {
                let u = URL(string: url)
                return Tab(id: UUID(), url: u, title: title, homeURL: home ? u : nil, lastActiveAt: now.addingTimeInterval(-ago))
            }
            let personal = Profile(
                id: UUID(), name: "Personal",
                favorites: [
                    tab("https://www.youtube.com", "YouTube", home: true), tab("https://github.com", "GitHub", home: true),
                    tab("https://open.spotify.com", "Spotify", home: true), tab("https://www.figma.com", "Figma", home: true),
                    tab("https://www.notion.so", "Notion", home: true), tab("https://claude.ai", "Claude", home: true),
                    tab("https://www.wikipedia.org", "Wikipedia", home: true), tab("https://www.reddit.com", "Reddit", home: true),
                ])
            let hero = tab("https://en.wikipedia.org/wiki/Aurora", "Aurora - Wikipedia", ago: 5)
            let reading = Node(
                id: UUID(),
                kind: .folder(
                    Folder(
                        title: "Reading list",
                        children: [
                            .tab(tab("https://www.swift.org", "Swift.org", home: true)),
                            .tab(tab("https://news.ycombinator.com", "Hacker News", home: true)),
                            .tab(tab("https://www.theverge.com", "The Verge", home: true)),
                        ])))
            let split = Node(
                id: UUID(),
                kind: .split(
                    Split(tabs: [
                        tab("https://developer.apple.com/swift/", "Swift - Apple Developer"),
                        tab("https://www.swift.org/documentation/", "Documentation | Swift.org"),
                    ])))
            let palette = SpaceTheme.palette
            let firstTheme = CommandLine.arguments.contains("--arc-theme") ? arcStyleTheme : palette[0].theme
            let home = Space(
                id: UUID(), title: "Personal", icon: palette[0].icon, theme: firstTheme, profileID: personal.id,
                pinned: [reading, .tab(tab("https://music.apple.com", "Apple Music", home: true))],
                today: [
                    .tab(hero), split, .tab(tab("https://www.nytimes.com", "The New York Times")),
                    .tab(tab("https://stackoverflow.com", "Stack Overflow")),
                ])
            let work = Space(
                id: UUID(), title: "Work", icon: palette[1].icon, theme: palette[1].theme, profileID: personal.id,
                pinned: [.tab(tab("https://linear.app", "Linear", home: true)), .tab(tab("https://slack.com", "Slack", home: true))])
            let study = Space(id: UUID(), title: "Study", icon: palette[4].icon, theme: palette[4].theme, profileID: personal.id)
            let side = Space(id: UUID(), title: "Side project", icon: palette[5].icon, theme: palette[5].theme, profileID: personal.id)
            var settings = Settings.default
            settings.hasCompletedOnboarding = !(argument(after: "--shot") ?? "").hasPrefix("welcome")
            return BrowserState(
                profiles: [personal], spaces: [home, work, study, side], selectedSpaceID: home.id, selectedTabID: hero.id,
                settings: settings)
        }

        /// Runs the screenshot script when `--screenshot` is given.
        static func runIfRequested(_ model: AppModel) {
            guard let path = argument(after: "--screenshot") else { return }
            let shot = argument(after: "--shot") ?? "hero"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                resizeWindow()
                if !shot.hasPrefix("welcome") {
                    // Visit every tab once so its real title and icon load.
                    let target = model.state.selectedTabID
                    let ids =
                        model.state.spaces.flatMap(model.state.orderedTabs(in:)).map(\.id)
                        + model.state.profiles.flatMap(\.favorites).map(\.id)
                    // --quick: skip visiting every tab (icons stay placeholders).
                    for id in ids where !CommandLine.arguments.contains("--quick") {
                        model.send(.tab(.select(id)))
                        try? await Task.sleep(for: .seconds(2.5))
                    }
                    if let first = model.state.spaces.first?.id { model.send(.space(.select(first))) }
                    switch shot {
                    case "start": model.send(.tab(.clearSelection))
                    case "split":
                        if let tab = model.state.spaces.first.flatMap({
                            $0.today.first { if case .split = $0.kind { true } else { false } }
                        })?.tabs.first {
                            model.send(.tab(.select(tab.id)))
                        }
                    default: if let target { model.send(.tab(.select(target))) }
                    }
                    try? await Task.sleep(for: .seconds(6))
                    await prepare(shot, model, path: path)
                }
                resizeWindow()  // also brings the window to the front, so its buttons are drawn active
                try? await Task.sleep(for: .seconds(1.5))
                if let hold = argument(after: "--hold").flatMap(Double.init) { try? await Task.sleep(for: .seconds(hold)) }
                let ok = capture(to: URL(fileURLWithPath: path))
                FileHandle.standardOutput.write(Data("demo: \(ok ? "✔ saved" : "✘ couldn't capture") \(path)\n".utf8))  // Debug tool output
                exit(ok ? 0 : 1)
            }
        }

        /// Scenes for Peek, SiteStyle, the mini player and Little Windows.
        private static func prepareFeature(_ shot: String, _ model: AppModel, path: String) async {
            if shot == "peek", let opener = model.state.selectedTabID, let profile = model.state.currentProfile {
                let url = URL(string: "https://www.swift.org/getting-started/")
                let tab = BrowserCore.Tab(id: UUID(), url: url, lastActiveAt: Date())
                _ = model.pages.page(for: tab, profile: profile, makeActive: false)
                model.pages.keptPageIDs.insert(tab.id)
                model.peek = PeekPage(id: tab.id, openerID: opener)
                try? await Task.sleep(for: .seconds(5))
            }
            if shot == "siteStyle", let page = model.selectedPage, let site = SiteStyle.site(of: page.state.url) {
                var siteStyle = SiteStyle()
                siteStyle.font = .serif
                siteStyle.hueRotation = 140
                model.saveSiteStyle(siteStyle, site: site)
                model.isSiteStyleEditorPresented = true
            }
            if shot == "miniPlayer" {
                let other = model.state.spaces.flatMap(model.state.orderedTabs(in:))
                    .first { $0.id != model.state.selectedTabID && model.pages.existingPage(for: $0.id) != nil }
                model.pausedMediaTabID = other?.id
            }
            if shot == "pip" { await pictureInPictureCheck(model) }
            if shot == "little" {
                if let blog = URL(string: "https://www.swift.org/blog/") { model.openLittleWindow(blog) }
                try? await Task.sleep(for: .seconds(6))
                let little = NSApp.windows.first {
                    $0.isVisible && ($0.identifier?.rawValue.contains(AppModel.littleWindowID) ?? false)
                }
                let ok = capture(to: URL(fileURLWithPath: path), window: little)
                exit(ok ? 0 : 1)
            }
        }

        /// Sets up the scene a `--shot` asks for (some save their own window and quit).
        private static func prepare(_ shot: String, _ model: AppModel, path: String) async {
            // --url with any other scene: that scene on that page (layout checks on a test page).
            if shot != "visit", let raw = argument(after: "--url"), let url = URL(string: raw) {
                model.send(.tab(.open(url, .newTab)))
                try? await Task.sleep(for: .seconds(5))
            }
            if shot == "command" { model.showCommandBar(.newTab) }
            if shot == "updateReady" { model.updateStatus = .ready(version: "0.1.3") }
            if shot == "updated" { UserDefaults.standard.set("0.1.0", forKey: "NeraLastSeenVersion") }
            if shot == "editSpace", let id = model.state.spaces.first?.id { model.editSpace(id) }
            if shot == "newSpace" { model.newSpace() }
            if shot == "collapsed" { model.toggleSidebar() }
            if shot == "private" {  // a private window (⇧⌘N), in a window of its own like the real one
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.contentViewController = NSHostingController(rootView: PrivateWindowRoot(registry: model.pages.registry))
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                try? await Task.sleep(for: .seconds(3))
                let ok = capture(to: URL(fileURLWithPath: path), window: window)
                exit(ok ? 0 : 1)
            }
            if shot.hasPrefix("settings") {  // settings-<section>: the Settings window on that section
                // The same view the Settings window shows, in a window of its own for the shot.
                let settings = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
                settings.title = "Settings"
                settings.center()
                settings.makeKeyAndOrderFront(nil)
                NSApp.activate()
                try? await Task.sleep(for: .seconds(2))
                let ok = capture(to: URL(fileURLWithPath: path), window: settings)
                exit(ok ? 0 : 1)
            }
            await prepareFeature(shot, model, path: path)
            if CommandLine.arguments.contains("--webkit"), let raw = argument(after: "--url"),
                let site = SiteEngines.site(of: URL(string: raw))
            {
                model.setEngine(.webKit, forSite: site)  // --webkit: show the --url page with WebKit
            }
            if shot == "visit", let raw = argument(after: "--url"), let url = URL(string: raw) {  // any page, e.g. an error
                model.send(.tab(.open(url, .newTab)))
                try? await Task.sleep(for: .seconds(8))
            }
            if shot == "retoggle" {  // hide and show the sidebar again (⌘S twice)
                if let dir = argument(after: "--frames") { recordFrames(to: dir, seconds: 3.5) }
                model.toggleSidebar()
                try? await Task.sleep(for: .seconds(1.5))
                model.toggleSidebar()
            }
            if shot == "swipe" { model.spaceSwipeOffset = -120 }  // halfway to the next Space
            if shot == "pageSwipe" { model.pageSwipeProgress = -0.75 }
        }

        /// Puts the welcome screen on the step named by `--shot welcome-<step>`, with made-up import data.
        static func prepare(_ flow: OnboardingFlow) {
            runAutopilot(flow)
            if PromoMode.flow == nil { PromoMode.flow = flow }  // SwiftUI keeps the first flow it makes
            guard isRequested, let shot = argument(after: "--shot"), shot.hasPrefix("welcome-") else { return }
            let name = shot.dropFirst("welcome-".count)
            guard let step = OnboardingFlow.Step.allCases.first(where: { "\($0)" == name }) else { return }
            showDemo(step, in: flow)
        }

        /// Puts the welcome screen on `step`, with made-up import data (never the Mac's real browser data).
        static func showDemo(_ step: OnboardingFlow.Step, in flow: OnboardingFlow) {
            let library = Self.library()
            let emoji = ["🏡", "💻", "📚", "🚀"]
            let spaces = library.spaces.enumerated().map { i, space in
                var copy = space
                copy.icon = .emoji(emoji[i % emoji.count])
                return copy
            }
            let preview = ArcImporter.Result(spaces: spaces, favorites: library.profiles.first?.favorites ?? [])
            let archive = (0..<214).map { i in
                ArchivedTab(
                    tab: Tab(id: UUID(), url: URL(string: "https://example.com/\(i)"), title: "Page \(i)", lastActiveAt: Date()),
                    spaceID: spaces[0].id, archivedAt: Date())
            }
            let extensions = [
                FoundExtension(
                    id: String(repeating: "a", count: 32), name: "1Password – Password Manager", wasEnabled: true, manifestVersion: 3),
                FoundExtension(id: String(repeating: "b", count: 32), name: "Dark Reader", wasEnabled: true, manifestVersion: 3),
                FoundExtension(id: String(repeating: "c", count: 32), name: "Grammarly", wasEnabled: false, manifestVersion: 3),
                FoundExtension(id: String(repeating: "d", count: 32), name: "uBlock Origin", wasEnabled: false, manifestVersion: 2),
            ]
            let summary =
                step == .summary
                ? ImportSummary(
                    spaces: 4, tabs: 23, folders: 2, favorites: 8, archived: 214, bookmarks: 342, history: 4_812, icons: 96)
                : nil
            let source = ImportSource.arc  // naming: import-reference
            flow.showDemo(step, source: source, preview: (preview, archive), extensions: extensions, summary: summary)
        }

        static func resizeWindow() {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            let parts = (argument(after: "--size") ?? "1440x900").split(separator: "x").compactMap { Double($0) }
            let size = parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : NSSize(width: 1440, height: 900)
            let screen = window.screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
            window.setFrame(
                NSRect(x: screen.minX + 40, y: screen.maxY - size.height - 40, width: size.width, height: size.height), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }

        /// Saves the app's main window (with its shadow) as PNG. CGWindowListCreateImage is gone from the SDK
        /// headers but still in CoreGraphics; looked up at runtime, Debug only.
        static func capture(to url: URL, window chosen: NSWindow? = nil) -> Bool {
            typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            guard let window = chosen ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
                let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
                let symbol = dlsym(handle, "CGWindowListCreateImage")
            else { return false }
            let create = unsafeBitCast(symbol, to: CreateImage.self)
            let optionIncludingWindow: UInt32 = 1 << 3
            let optionAboveWindow: UInt32 = 1 << 1
            // With a sheet open, capture the window's area with what's above it (the sheet), not just the window.
            var rect = CGRect.null
            var options = optionIncludingWindow
            if window.attachedSheet != nil, let screen = NSScreen.screens.first {
                let f = window.frame
                rect = CGRect(x: f.minX, y: screen.frame.maxY - f.maxY, width: f.width, height: f.height)
                options |= optionAboveWindow
            }
            guard let image = create(rect, options, UInt32(window.windowNumber), 0)?.takeRetainedValue(),
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return false }
            return (try? png.write(to: url)) != nil
        }
    }
#endif

#if DEBUG && os(macOS)
    /// --arc-theme: a Space that looks like one brought over from Arc (exact color, white text).
    private let arcStyleTheme: SpaceTheme = {
        let exact = ExactColors(
            base: RGBA(red: 0.13, green: 0.38, blue: 0.29), intensity: 0.8, focusLight: RGBA(red: 0.57, green: 0.69, blue: 0.64),
            focusDark: RGBA(red: 0.3, green: 0.5, blue: 0.43), textOnColor: .white)
        return SpaceTheme(hue: exact.base.hsb.hue, saturation: exact.base.hsb.saturation, appearance: .system, exact: exact)
    }()
#endif
