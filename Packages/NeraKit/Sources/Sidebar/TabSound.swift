// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

/// The speaker on a tab playing sound, or muted: click to mute or unmute it, as in Arc.
struct TabSoundButton: View {
    let host: any SidebarHost
    let tab: Tab
    /// A small round badge on a Favorite's tile instead of a plain symbol in a row.
    var isBadge = false

    var body: some View {
        let audio = host.audio(of: tab.id)
        if audio.playing || audio.muted {
            Button {
                host.toggleMute(tab.id)
            } label: {
                Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: isBadge ? 8 : 11, weight: .semibold))
                    .frame(width: isBadge ? 16 : 18, height: isBadge ? 16 : 18)
                    .background { if isBadge { Circle().fill(.background) } }
                    .shadow(color: .black.opacity(isBadge ? 0.2 : 0), radius: 2, y: 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(audio.muted ? .secondary : .primary)
            .help(audio.muted ? "Unmute" : "Mute")
            .accessibilityLabel(audio.muted ? "Unmute \(tab.displayTitle)" : "Mute \(tab.displayTitle)")
            .accessibilityIdentifier("sidebar.tab.sound")
            .transition(.scale.combined(with: .opacity))
        }
    }
}

extension View {
    /// Tells VoiceOver (and UI tests) that the tab plays sound or is muted, and lets it mute or unmute.
    func tabSoundAccessibility(host: any SidebarHost, tab: Tab) -> some View {
        let audio = host.audio(of: tab.id)
        return
            self
            .accessibilityValue(audio.muted ? "Muted" : (audio.playing ? "Playing sound" : ""))
            .accessibilityAction(named: audio.muted ? "Unmute" : "Mute") { host.toggleMute(tab.id) }
    }
}
