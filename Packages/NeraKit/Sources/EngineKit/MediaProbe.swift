// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A script that tells whether a page has video or audio in a format its engine can't play: standard
/// Chromium has no H.264/AAC. It returns `"unsupported"` when a media element failed because no stream could be
/// decoded (Chromium names this in the error message: "…NO_SUPPORTED_STREAMS…", "…NOT_SUPPORTED…"), or when every
/// `<source>` it offered has a type the engine can't play; otherwise `"ok"`. A missing or broken file
/// ("Format error") isn't flagged: another engine wouldn't help. DRM (EME) failures aren't detected.
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
          return [...document.querySelectorAll('video, audio')].some(unsupported) ? 'unsupported' : 'ok';
        })()
        """

    /// The result for media the engine can't play.
    public static let unsupported = "unsupported"
}
