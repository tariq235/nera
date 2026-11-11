// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import Foundation
    import SwiftUI

    /// The promo's scenes. Each one is real use of Nera: model actions are what the shortcuts and clicks shown do.
    extension PromoMode {
        static func setUp(_ scene: String, _ model: AppModel) async {
            // --exact <hex>: the first Space as if imported from Arc with that color (for comparing with Arc).
            if let hex = DemoMode.argument(after: "--exact").flatMap({ UInt32($0, radix: 16) }), let space = model.state.spaces.first {
                let base = RGBA(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
                let theme = SpaceTheme(
                    hue: base.hsb.hue, saturation: base.hsb.saturation, appearance: .light, exact: ExactColors(base: base))
                model.send(.space(.customize(space.id, icon: nil, theme: theme)))
            }
            switch scene {
            case "import":
                // Pages aren't made behind the welcome screen: make them now, so the sidebar it reveals has its
                // site icons and the pull request is already on screen.
                if let profile = model.state.currentProfile {
                    let tabs = model.state.spaces.flatMap(model.state.orderedTabs(in:)) + profile.favorites
                    for tab in tabs {
                        _ = model.pages.page(for: tab, profile: profile, makeActive: tab.id == model.state.selectedTabID)
                    }
                }
                try? await Task.sleep(for: .seconds(8))
                if let flow { DemoMode.showDemo(.spaces, in: flow) }
                try? await Task.sleep(for: .seconds(1.5))
            case "peeklink":  // a pinned tab on a site with links elsewhere (--webkit: in WebKit, as X is)
                if CommandLine.arguments.contains("--webkit") { model.setEngine(.webKit, forSite: "wikipedia.org") }
                model.send(.tab(.open(URL(string: "https://en.wikipedia.org/wiki/Aurora")!, .newTab)))
                if let id = model.state.selectedTabID {
                    // --favorite: as a Favorite (like X in the sidebar's top grid), else a pinned tab.
                    model.send(.tab(CommandLine.arguments.contains("--favorite") ? .addToFavorites(id) : .togglePin(id)))
                    model.send(.tab(.select(id)))
                }
                try? await Task.sleep(for: .seconds(6))
            case "hero":
                if let repoTab = tab(model, containing: "tariq235/nera", exact: true) { model.send(.tab(.select(repoTab))) }
                try? await Task.sleep(for: .seconds(2))
            default: break
            }
        }

        static func play(_ scene: String, _ model: AppModel) async {
            switch scene {
            case "import": await importScene(model)
            case "hero": await heroScene(model)
            case "work": await workScene(model)
            case "spaces": await spacesScene(model)
            case "theme": await themeScene(model)
            case "peeklink": await peekLinkScene(model)
            case "sitecontrols":  // the address bar's site controls, opened by a click
                await wait(0.5)
                model.isSiteControlsPresented = true
                await wait(2)
            case "capture":  // File › Capture…, waiting for an area
                await wait(0.5)
                model.startCapture()
                await wait(1.5)
            case "command":  // the command bar completing an address, held still (for comparing with Arc)
                shortcut(["⌘", "T"]) { model.showCommandBar(.newTab) }
                await wait(0.5)
                await type(DemoMode.argument(after: "--type") ?? "git", every: 0.09)
                await wait(1.5)
            default: FileHandle.standardError.write(Data("promo: unknown scene \(scene)\n".utf8))
            }
        }

        /// Arc's Spaces picked, the import counting up, then the sidebar, rebuilt.
        private static func importScene(_ model: AppModel) async {
            await wait(1.0)
            if let flow { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { DemoMode.showDemo(.summary, in: flow) } }
            log("importSummary")
            await wait(2.8)
            log("reveal")
            withAnimation(.easeInOut(duration: 0.55)) { model.finishWelcome() }
            await wait(2.4)
        }

        /// The repository's home: the README.
        private static func heroScene(_ model: AppModel) async {
            await wait(0.8)
            await scrollPage(model, by: 520)
            await wait(2.4)
        }

        /// Shipping a release: the pull request, ⌘T to the CI run, Split View with the sketch and the docs, Peek, a
        /// Little Window.
        private static func workScene(_ model: AppModel) async {
            await wait(0.6)
            await scrollPage(model, by: 640)
            await wait(1.3)
            shortcut(["⌘", "T"]) { model.showCommandBar(.newTab) }
            await wait(0.45)
            await type("actions", every: 0.07)
            await wait(0.35)
            shortcut(["↓"]) { press(125, "\u{F701}") }  // NSDownArrowFunctionKey
            await wait(0.3)
            shortcut(["↩"]) { press(36, "\r") }
            log("switched")
            await wait(1.5)
            // ⌃⇧=: a new tab in Split View; "excal" completes to excalidraw.com.
            shortcut(["⌃", "⇧", "="]) { model.showCommandBar(.splitWithCurrent) }
            await wait(0.45)
            await type("excal", every: 0.08)
            await wait(0.35)
            shortcut(["↩"]) { press(36, "\r") }
            log("split2")
            await wait(1.3)
            if let current = model.state.selectedTabID {
                for title in ["architecture.md", "SwiftUI"] {
                    if let other = tab(model, containing: title) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.send(.tab(.splitWith(current, other: other))) }
                        log("splitMore")
                        await wait(0.7)
                    }
                }
            }
            await wait(1.2)
            // Peek: a link opened over the page.
            if let opener = model.state.selectedTabID, let profile = model.state.currentProfile {
                let peek = BrowserCore.Tab(id: UUID(), url: URL(string: "\(repo)/releases"), lastActiveAt: Date())
                _ = model.pages.page(for: peek, profile: profile, makeActive: false)
                model.pages.keptPageIDs.insert(peek.id)
                await wait(1.2)
                log("peek")
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.peek = PeekPage(id: peek.id, openerID: opener) }
                await wait(2.2)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { model.peek = nil }
                await wait(0.8)
            }
            // A Little Window, for a link from another app.
            log("little")
            if let url = URL(string: "\(repo)/releases/tag/v0.1.3") { model.openLittleWindow(url) }
            await wait(2.6)
        }

        /// Clicks (a real mouse click in the window) a link to another site in a pinned tab: it must open in Peek and
        /// the tab must stay on its page. Prints what happened.
        private static func peekLinkScene(_ model: AppModel) async {
            guard let id = model.state.selectedTabID, let page = model.selectedPage, let window = page.view.window else { return }
            let before = page.state.url
            let script = """
                (() => { const a = [...document.querySelectorAll('#bodyContent a[href^="https://"]')]
                  .find(a => !/(^|\\.)(wikipedia|wikimedia|wikidata|mediawiki)\\.org$/.test(new URL(a.href).hostname));
                  if (!a) return '';
                  a.scrollIntoView({block: 'center'}); const r = a.getBoundingClientRect();
                  return [r.left + r.width / 2, r.top + r.height / 2, a.href].join(' '); })()
                """
            guard let found = await page.evaluate(script), case let parts = found.split(separator: " "), parts.count == 3,
                let x = Double(parts[0]), let y = Double(parts[1])
            else { return FileHandle.standardOutput.write(Data("peeklink: no outside link found\n".utf8)) }  // Debug tool output
            await wait(0.8)
            let inWindow = page.view.convert(NSPoint(x: x, y: page.view.isFlipped ? y : page.view.bounds.height - y), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(
                    with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                {
                    window.sendEvent(event)
                }
            }
            await wait(3)
            let after = model.pages.existingPage(for: id)?.state.url
            let report =
                "peeklink: \(String(describing: Swift.type(of: page))) link \(parts[2]) | peek=\(model.peek != nil) peekURL=\(model.peekPage?.state.url?.absoluteString ?? "-") "
                + "| pinned stayed=\(after == before) (\(after?.absoluteString ?? "-"))\n"
            FileHandle.standardOutput.write(Data(report.utf8))  // Debug tool output
        }

        /// Swipes across the Spaces, each with its own colors, and back.
        private static func spacesScene(_ model: AppModel) async {
            logSpace(model)
            await wait(0.7)
            for direction in [-1.0, -1, -1, 1, 1, 1] {
                await swipe(model, toward: direction)
                logSpace(model)
                await wait(direction < 0 ? 0.75 : 0.45)
            }
            await wait(0.4)
        }

        /// The Space's look, changed live: colors and grain.
        private static func themeScene(_ model: AppModel) async {
            guard let space = model.state.selectedSpace else { return }
            await wait(0.5)
            model.editSpace(space.id)
            await wait(0.9)
            for look in SpaceTheme.palette.prefix(7).dropFirst() {
                withAnimation(.easeInOut(duration: 0.35)) { model.send(.space(.customize(space.id, icon: look.icon, theme: look.theme))) }
                logSpace(model)
                await wait(0.5)
            }
            await wait(0.6)
        }

        /// The fingers' drag, then the spring the real gesture ends with (SwipeNavigation).
        private static func swipe(_ model: AppModel, toward direction: CGFloat) async {
            let steps = 12
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                model.spaceSwipeOffset = direction * 170 * (1 - pow(1 - t, 2))
                await wait(0.016)
            }
            let ids = model.state.spaces.map(\.id)
            let index = ids.firstIndex(of: model.state.selectedSpaceID) ?? 0
            let next = direction < 0 ? index + 1 : index - 1
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                model.spaceSwipeOffset = 0
                if ids.indices.contains(next) { model.send(.space(.select(ids[next]))) }
            }
        }

        /// A tab in any Space whose title or address contains `text`.
        static func tab(_ model: AppModel, containing text: String, exact: Bool = false) -> UUID? {
            model.state.spaces.flatMap(model.state.orderedTabs(in:)).first { tab in
                let address = tab.url?.absoluteString ?? ""
                return exact ? address == "\(repo)" || address == "\(repo)/" : (tab.displayTitle.contains(text) || address.contains(text))
            }?.id
        }
    }
#endif
