// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The media watcher (whether the page plays sound): the same text as `MediaWatch.script` in EngineKit, which explains
// it; MediaWatchTests keeps the two equal. Compiled in, because the sandboxed renderer can't read files.
#pragma once

static const char kNeraMediaWatch[] = R"NERAJS(
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
)NERAJS";
