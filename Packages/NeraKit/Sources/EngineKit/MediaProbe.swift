// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A script that tells whether a page has video or audio in a format its engine can't play: standard
/// Chromium has no H.264/AAC. It returns `"unsupported"` when a media element failed because no stream could be
/// decoded (Chromium names this in the error message: "…NO_SUPPORTED_STREAMS…", "…NOT_SUPPORTED…"), or when every
/// `<source>` it offered has a type the engine can't play; otherwise `"ok"`. A missing or broken file
/// ("Format error") isn't flagged: another engine wouldn't help. DRM (EME) failures aren't detected.
///
/// Players that stream through Media Source Extensions (X, most social and news sites) never put an unplayable type
/// on a media element: they ask `MediaSource.isTypeSupported` and show their own error. So a page that fetched HLS
/// playlists or MP4 video (successfully: a missing file isn't another engine's job) while the engine can't play
/// H.264 is flagged too.
public enum MediaProbe {
    /// The script, for ``WebPage/evaluate(_:)``.
    public static let script = """
        (() => {
          const unsupported = m => {
            if (m.error && m.error.code === 4) return /NO_SUPPORTED|NOT_SUPPORTED|no supported|not supported/i.test(m.error.message || '');
            if (m.networkState !== 3) return false;
            const sources = [...m.querySelectorAll('source')];
            return sources.length > 0 && sources.every(s => s.type && m.canPlayType(s.type) === '');
          };
          if ([...document.querySelectorAll('video, audio')].some(unsupported)) return 'unsupported';
          const h264 = window.MediaSource && MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"');
          const streamed = performance.getEntriesByType('resource')
            .some(e => /\\.(m3u8|mp4)(\\?|$)/i.test(e.name) && e.initiatorType !== 'link' && e.responseStatus >= 200 && e.responseStatus < 300);
          return !h264 && streamed && document.querySelector('video') ? 'unsupported' : 'ok';
        })()
        """

    /// The result for media the engine can't play.
    public static let unsupported = "unsupported"
}
