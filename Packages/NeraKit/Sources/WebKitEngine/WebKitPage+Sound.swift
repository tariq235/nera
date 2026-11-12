// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import WebKit

/// Sound: whether the page plays it (``MediaWatch`` in every frame, in Nera's isolated script world) and muting it.
/// WebKit has no public API for either, so muting goes through the watcher too: it mutes the frames' media
/// elements and puts back the ones it muted.
extension WebKitPage {
    /// The name the watcher reports under.
    static let mediaHandlerName = "neraMedia"

    /// Installs the watcher in every frame of pages made with `configuration`, reporting to `handler`.
    static func installMediaWatch(in configuration: WKWebViewConfiguration, handler: any WKScriptMessageHandler) {
        let source = """
            window.__neraMedia = (\(MediaWatch.script))((audible) => window.webkit.messageHandlers.\(mediaHandlerName)
              .postMessage({ frame: __neraFrame, audible }));
            """
        // Each frame names itself, so the page can combine their reports.
        let named = "const __neraFrame = Math.random().toString(36).slice(2);\n" + source
        let script = WKUserScript(source: named, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(handler, contentWorld: .defaultClient, name: mediaHandlerName)
    }

    /// A frame's report: `{ frame, audible }`. Only Nera's isolated world can post it.
    func mediaReport(_ body: Any, from frameInfo: WKFrameInfo) {
        guard !isClosed, let report = body as? [String: Any], let frame = report["frame"] as? String,
            let audible = report["audible"] as? Bool
        else { return }
        mediaFrameInfos[frame] = frameInfo
        // A muted tab mutes a frame's media as soon as it starts playing.
        if audible, state.isMuted { setFrameMuted(true, frameInfo) }
        if mediaFrames.report(frame: frame, audible: audible) { update { $0.isAudible = mediaFrames.isAudible } }
    }

    /// The main frame moved to another document: its frames' reports no longer apply.
    func resetMediaFrames() {
        mediaFrameInfos = [:]
        if mediaFrames.reset() { update { $0.isAudible = false } }
    }

    func setMuted(_ muted: Bool) {
        guard !isClosed, muted != state.isMuted else { return }
        update { $0.isMuted = muted }
        for info in mediaFrameInfos.values { setFrameMuted(muted, info) }
        if mediaFrameInfos.isEmpty { setFrameMuted(muted, nil) }  // the main frame, before it reported
    }

    private func setFrameMuted(_ muted: Bool, _ frame: WKFrameInfo?) {
        webView.evaluateJavaScript("window.__neraMedia?.setMuted(\(muted))", in: frame, in: .defaultClient) { _ in }
    }
}

/// Passes the watcher's messages on without the page's content controller keeping the page alive.
final class MediaMessageProxy: NSObject, WKScriptMessageHandler {
    weak var page: WebKitPage?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { page?.mediaReport(message.body, from: message.frameInfo) }
    }
}
