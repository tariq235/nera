// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation

/// Nera's Picture in Picture scripts. They run as a click on the page (``WebPage/evaluateAsUserGesture(_:)``), since
/// the web lets a page float a video only after one, and only touch the page's own `<video>` elements.
enum PictureInPictureScript {
    /// Floats the largest video playing with sound. Answers "entered", "already" (something already floats), "none"
    /// (no such video) or "failed: <reason>".
    static let enter = """
        (async () => {
          if (document.pictureInPictureElement) return 'already';
          if (!document.pictureInPictureEnabled) return 'failed: disabled';
          const video = [...document.querySelectorAll('video')]
            .filter(v => !v.paused && !v.ended && !v.muted && v.volume > 0 && !v.disablePictureInPicture &&
              v.videoWidth >= 160 && v.videoHeight >= 90)
            .sort((a, b) => b.videoWidth * b.videoHeight - a.videoWidth * a.videoHeight)[0];
          if (!video) return 'none';
          try { await video.requestPictureInPicture(); return 'entered'; } catch (e) { return 'failed: ' + e.name; }
        })()
        """

    /// Puts a floating video back in its page, still playing if it was (WebKit pauses it on the way back). Answers
    /// "exited" or "none".
    static let exit = """
        (async () => {
          const video = document.pictureInPictureElement;
          if (!video) return 'none';
          const wasPlaying = !video.paused;
          try { await document.exitPictureInPicture(); } catch (e) { return 'none'; }
          await new Promise(done => setTimeout(done, 250));
          if (wasPlaying && video.paused) await video.play().catch(() => {});
          return 'exited';
        })()
        """
}

/// Videos pop out when you leave their tab (Settings › General), as in Arc: switching away from a tab playing a
/// video with sound floats the video in Picture in Picture; coming back to the tab puts it back in the page.
extension AppModel {
    /// Tabs left the screen or came back (``PageManager/visibilityChanged``). Runs after the change, outside the
    /// view update that caused it.
    func tabsVisibilityChanged(hidden: Set<UUID>, shown: Set<UUID>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for id in shown where pictureInPictureTabs.contains(id) {
                pictureInPictureTabs.remove(id)
                guard let page = pages.existingPage(for: id), await Self.isOnScreen(page) else { continue }
                _ = await page.evaluateAsUserGesture(PictureInPictureScript.exit)
            }
            guard store.state.settings.autoPictureInPicture else { return }
            for id in hidden {
                // Only pages playing sound are asked: switching tabs stays free for every other page.
                guard let page = pages.existingPage(for: id), page.state.isAudible else { continue }
                let answer = await page.evaluateAsUserGesture(PictureInPictureScript.enter)
                // The tab may have come back while the video was floating out.
                if answer == "entered" { pictureInPictureTabs.insert(id) }
                if pages.visibleTabIDs.contains(id), answer == "entered" {
                    pictureInPictureTabs.remove(id)
                    _ = await page.evaluateAsUserGesture(PictureInPictureScript.exit)
                }
            }
        }
    }

    /// Waits (up to two seconds) for the page to be in a window again: WebKit puts a floating video back only into a
    /// page on screen, and the tab is reported shown before the window has drawn it.
    private static func isOnScreen(_ page: any WebPage) async -> Bool {
        for _ in 0..<40 {
            if page.view.window != nil { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
