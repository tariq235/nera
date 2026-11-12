// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import DesignSystem
import EngineKit
import SecurityPolicy
import SwiftUI

/// Nera's media scripts. They only touch `<video>` and `<audio>` elements in the page's own document.
enum MediaScript {
    /// Pauses whatever is playing, or resumes the most recently played element. Answers "playing", "paused" or
    /// "none".
    static let toggle = """
        (() => {
          const all = [...document.querySelectorAll('video, audio')];
          const playing = all.filter(m => !m.paused && !m.ended);
          if (playing.length) { playing.forEach(m => m.pause()); return 'paused'; }
          const last = all.filter(m => m.currentTime > 0).sort((a, b) => b.currentTime - a.currentTime)[0] || all[0];
          if (!last) return 'none';
          last.play();
          return 'playing';
        })()
        """
}

extension AppModel {
    /// The tab the mini player is for: a tab other than the visible one that's playing sound, or one the user
    /// paused from the mini player (so it can be resumed).
    var mediaTab: BrowserCore.Tab? {
        let selected = state.selectedTabID
        let tabs = state.spaces.flatMap(state.orderedTabs(in:)) + (state.currentProfile?.favorites ?? [])
        if let audible = tabs.first(where: { $0.id != selected && pages.existingPage(for: $0.id)?.state.isAudible == true }) {
            return audible
        }
        guard let paused = pausedMediaTabID, paused != selected, pages.existingPage(for: paused) != nil else { return nil }
        return tabs.first { $0.id == paused }
    }

    /// Plays or pauses the media of a background tab.
    func toggleMedia(_ tab: BrowserCore.Tab) {
        guard let page = pages.existingPage(for: tab.id) else { return }
        Task {
            let result = await page.evaluate(MediaScript.toggle)
            pausedMediaTabID = result == "paused" ? tab.id : nil
        }
    }

    /// Hides the mini player for a paused tab.
    func dismissMedia() { pausedMediaTabID = nil }
}

/// A small player above the sidebar's bottom bar for a tab playing in the background: its icon and title (click
/// to go to it), play/pause and mute.
struct MiniPlayer: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let tab = model.mediaTab, let page = model.pages.existingPage(for: tab.id) {
                let isPlaying = page.state.isAudible || (page.state.isMuted && model.pausedMediaTabID != tab.id)
                HStack(spacing: 8) {
                    Button {
                        model.send(.tab(.select(tab.id)))
                    } label: {
                        HStack(spacing: 8) {
                            SiteIcon(url: tab.url, size: 16, png: model.favicon(for: tab))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(page.state.title.isEmpty ? tab.displayTitle : page.state.title)
                                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(tab.url.map { DisplayURL.short($0) } ?? "")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Go to this tab")
                    control(isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause" : "Play") { model.toggleMedia(tab) }
                        .accessibilityIdentifier("miniPlayer.playPause")
                    let muted = page.state.isMuted
                    control(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: muted ? "Unmute" : "Mute") {
                        model.toggleMute(tab.id)
                    }
                    .accessibilityIdentifier("miniPlayer.mute")
                    if !isPlaying {
                        control("xmark", help: "Close") { model.dismissMedia() }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .surface(.resting, cornerRadius: 11)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Now playing")
                .accessibilityIdentifier("miniPlayer")
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.mediaTab?.id)
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.8))
        .help(help)
        .accessibilityLabel(help)
    }
}

// ⌘1–9: Favorites, then the Space's pinned tabs, in sidebar order (⌘9 is always the last one, as in other browsers).
extension AppModel {
    /// The tabs ⌘1–9 jump to.
    public var shortcutTabs: [BrowserCore.Tab] {
        (state.currentProfile?.favorites ?? []) + (state.selectedSpace?.pinned.flatMap(\.tabs) ?? [])
    }

    /// The tab ⌘`number` selects, if there is one.
    public func shortcutTab(_ number: Int) -> BrowserCore.Tab? {
        let tabs = shortcutTabs
        guard !tabs.isEmpty, (1...9).contains(number) else { return nil }
        if number == 9 { return tabs.last }
        return tabs.indices.contains(number - 1) ? tabs[number - 1] : nil
    }

    /// Selects the tab for ⌘`number`.
    public func selectShortcutTab(_ number: Int) {
        if let tab = shortcutTab(number) { send(.tab(.select(tab.id))) }
    }
}
