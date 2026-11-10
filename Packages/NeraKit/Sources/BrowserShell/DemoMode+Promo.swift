// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import Foundation
    import SwiftUI

    /// `--promo <scene> --record <dir>` (Debug only): plays one scripted scene of Nera's promo video and records
    /// Nera's windows at full (Retina) resolution while it plays, with a log of what happened when (keys pressed,
    /// Space colors) for the video's overlays. Everything happens inside Nera (keys go to its own window), so a
    /// recording never touches the Mac's real keyboard or pointer. `scripts/promo/` turns the frames into the video.
    @MainActor
    enum PromoMode {
        /// The welcome screen's flow, for the import scene.
        static weak var flow: OnboardingFlow?
        static var recorder: FrameRecorder?
        static var scene: String? { DemoMode.argument(after: "--promo") }

        static func runIfRequested(_ model: AppModel) {
            guard let scene, let dir = DemoMode.argument(after: "--record") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                DemoMode.resizeWindow()
                await loadPages(model)
                await setUp(scene, model)
                DemoMode.resizeWindow()
                try? await Task.sleep(for: .seconds(1))
                let recorder = FrameRecorder(dir: dir)
                self.recorder = recorder
                recorder.start()
                try? await Task.sleep(for: .seconds(0.4))
                await play(scene, model)
                try? await Task.sleep(for: .seconds(0.4))
                let count = await recorder.stop()
                FileHandle.standardOutput.write(Data("promo: \(scene) \(count) frames in \(dir)\n".utf8))  // Debug tool output
                exit(count > 0 ? 0 : 1)
            }
        }

        // MARK: The library on screen

        static let repo = "https://github.com/tariq235/nera"

        /// A developer's sidebar while shipping Nera 0.1.4: the real repository, its pull request, CI runs and
        /// docs. Only public pages, nobody signed in.
        static func library() -> BrowserState {
            let now = Date()
            func tab(_ url: String, _ title: String, home: Bool = false, ago: TimeInterval = 600) -> Tab {
                Tab(
                    id: UUID(), url: URL(string: url), title: title, homeURL: home ? URL(string: url) : nil,
                    lastActiveAt: now.addingTimeInterval(-ago))
            }
            let profile = Profile(
                id: UUID(), name: "Personal",
                favorites: [
                    tab("https://github.com", "GitHub", home: true), tab("https://www.youtube.com", "YouTube", home: true),
                    tab("https://www.figma.com", "Figma", home: true), tab("https://www.notion.so", "Notion", home: true),
                    tab("https://linear.app", "Linear", home: true), tab("https://open.spotify.com", "Spotify", home: true),
                    tab("https://claude.ai", "Claude", home: true), tab("https://excalidraw.com", "Excalidraw", home: true),
                ])
            let pr = tab("\(repo)/pull/9", "Release 0.1.4 · Pull Request #9", ago: 5)
            let release = Node(
                id: UUID(),
                kind: .folder(
                    Folder(
                        title: "Release 0.1.4",
                        children: [
                            .tab(tab("\(repo)/actions", "Actions · tariq235/nera", home: true)),
                            .tab(tab("\(repo)/releases", "Releases · tariq235/nera", home: true)),
                            .tab(tab("\(repo)/blob/main/CHANGELOG.md", "CHANGELOG.md", home: true)),
                        ])))
            let palette = SpaceTheme.palette
            let nera = Space(
                id: UUID(), title: "Nera", icon: .emoji("🌌"), theme: palette[0].theme, profileID: profile.id,
                pinned: [release, .tab(tab(repo, "tariq235/nera", home: true))],
                today: [
                    .tab(pr), .tab(tab("https://excalidraw.com", "Excalidraw")),
                    .tab(tab("\(repo)/blob/main/docs/architecture.md", "architecture.md")),
                    .tab(tab("https://developer.apple.com/documentation/swiftui", "SwiftUI | Apple Developer")),
                ])
            let design = Space(
                id: UUID(), title: "Design", icon: .emoji("🎨"), theme: palette[1].theme, profileID: profile.id,
                today: [.tab(tab("https://developer.apple.com/design/human-interface-guidelines", "Human Interface Guidelines"))])
            let research = Space(
                id: UUID(), title: "Research", icon: .emoji("📚"), theme: palette[4].theme, profileID: profile.id,
                today: [.tab(tab("https://en.wikipedia.org/wiki/Aurora", "Aurora - Wikipedia"))])
            let home = Space(
                id: UUID(), title: "Home", icon: .emoji("🏡"), theme: palette[5].theme, profileID: profile.id,
                today: [.tab(tab("https://en.wikipedia.org/wiki/Saturn", "Saturn - Wikipedia"))])
            var settings = Settings.default
            settings.hasCompletedOnboarding = scene != "import"
            return BrowserState(
                profiles: [profile], spaces: [nera, design, research, home], selectedSpaceID: nera.id, selectedTabID: pr.id,
                settings: settings)
        }

        /// Visits every page once so titles and site icons are real, then comes back to the first Space's first tab.
        private static func loadPages(_ model: AppModel) async {
            let ids =
                model.state.spaces.flatMap(model.state.orderedTabs(in:)).map(\.id) + model.state.profiles.flatMap(\.favorites).map(\.id)
            let target = model.state.selectedTabID
            for id in ids {
                model.send(.tab(.select(id)))
                try? await Task.sleep(for: .seconds(1.6))
            }
            if let first = model.state.spaces.first?.id { model.send(.space(.select(first))) }
            if let target { model.send(.tab(.select(target))) }
            try? await Task.sleep(for: .seconds(3))
        }

        // MARK: Helpers for scenes

        static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

        /// Notes a moment for the video (keys shown as keycaps, a Space's colors…).
        static func log(_ type: String, _ fields: [String: Any] = [:]) { recorder?.log(type, fields) }

        /// Shows keycaps in the video for a shortcut, then does what the shortcut does.
        static func shortcut(_ keys: [String], _ perform: () -> Void) {
            log("keys", ["keys": keys])
            perform()
        }

        /// Types into Nera's key window, as the keyboard would.
        static func type(_ text: String, every interval: Double = 0.11) async {
            log("type", ["text": text])
            for character in text {
                press(0, String(character))
                await wait(interval)
            }
        }

        static func press(_ keyCode: UInt16, _ characters: String) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            for kind in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: kind, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: keyCode)
                {
                    NSApp.sendEvent(event)
                }
            }
        }

        /// Scrolls the selected page smoothly (the page's own smooth scrolling).
        static func scrollPage(_ model: AppModel, by dy: Int) async {
            _ = await model.selectedPage?.evaluate("window.scrollBy({top: \(dy), behavior: 'smooth'}); 'ok'")
        }

        /// Logs the selected Space's colors, for the video's background.
        static func logSpace(_ model: AppModel) {
            guard let theme = model.state.selectedSpace?.theme else { return }
            log("space", ["hue": theme.hue, "saturation": theme.saturation, "secondaryHue": theme.secondaryHue ?? theme.hue])
        }
    }
#endif
