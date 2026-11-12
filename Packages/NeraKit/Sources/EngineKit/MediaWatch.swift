// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Whether a page is playing sound, for the tab's speaker icon, Mute, the mini player and Picture in Picture.
/// Neither engine says so (CEF has no callback; WebKit only privately), so each frame of the page watches its own
/// `<video>` and `<audio>` elements and reports changes.
///
/// The engines install ``script`` in every frame before the page's scripts run: WebKit as a user script in Nera's
/// isolated world, Chromium from the renderer helper (`Apps/macOS/ChromiumHelper/media_watch.h` holds the same text;
/// a test keeps the two equal). It's a function taking `report(audible)`, which only Nera's code can reach, and
/// returning `{ setMuted(on) }` for engines that can't mute a page themselves (WebKit).
///
/// A page could fake media events, but an event only makes the watcher look again at the real elements, so a page
/// can at most make its own tab look silent or playing. Media never added to the page (`new Audio()`) and players
/// inside closed shadow roots aren't seen.
public enum MediaWatch {
    /// The watcher: `(function (report) { … })`.
    public static let script = #"""
        (function (report) {
          'use strict';
          let last = false;
          let muting = false;
          const mutedByNera = new WeakSet();
          const sounds = (m) => !m.muted || mutedByNera.has(m);
          // A stream (a call, a camera) has sound while it carries a live audio track; a file once it decodes audio.
          const hasSound = (m) => m.srcObject instanceof MediaStream
            ? m.srcObject.getAudioTracks().some((t) => t.enabled && t.readyState === 'live')
            : m.webkitAudioDecodedByteCount === undefined || m.webkitAudioDecodedByteCount > 0 || m.currentTime < 1;
          const playing = (m) => !m.paused && !m.ended && sounds(m) && m.volume > 0 && hasSound(m);
          const media = () => document.querySelectorAll('video, audio');
          const silence = (m) => { if (muting && !m.muted) { mutedByNera.add(m); m.muted = true; } };
          const check = (event) => {
            if (event && event.target instanceof HTMLMediaElement) silence(event.target);
            let now = false;
            for (const m of media()) if (playing(m)) { now = true; break; }
            if (now !== last) { last = now; report(now); }
          };
          for (const type of ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied', 'abort', 'error']) {
            document.addEventListener(type, check, true);
          }
          // A video without sound decodes no audio: look again once it has played a moment.
          document.addEventListener('playing', () => setTimeout(check, 1500), true);
          window.addEventListener('pagehide', () => { if (last) { last = false; report(false); } }, true);
          return {
            // Mutes the page's media (for engines that can't mute a page themselves); the page still counts as
            // playing sound, as a muted tab does.
            setMuted(on) {
              muting = on;
              for (const m of media()) {
                if (on) silence(m);
                else if (mutedByNera.has(m)) { mutedByNera.delete(m); m.muted = false; }
              }
            },
          };
        })
        """#

    /// What a page's frames reported, combined: the page is audible while any frame is.
    public struct Frames: Equatable, Sendable {
        private var audible: Set<String> = []

        /// No frame audible.
        public init() {}

        /// Whether any frame is playing sound.
        public var isAudible: Bool { !audible.isEmpty }

        /// Records a frame's report; returns whether the page's state changed.
        public mutating func report(frame: String, audible isAudible: Bool) -> Bool {
            let before = self.isAudible
            if isAudible { audible.insert(frame) } else { audible.remove(frame) }
            return before != self.isAudible
        }

        /// Forgets a frame that went away; returns whether the page's state changed.
        public mutating func remove(frame: String) -> Bool { report(frame: frame, audible: false) }

        /// Forgets every frame (the page moved to another document); returns whether the state changed.
        public mutating func reset() -> Bool {
            let before = isAudible
            audible.removeAll()
            return before
        }
    }
}
