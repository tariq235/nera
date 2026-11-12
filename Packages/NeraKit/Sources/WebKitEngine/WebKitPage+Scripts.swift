// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import WebKit

/// Nera's own scripts in the page: plain ones (SiteStyles, the mini player), and ones that run as a click (Picture in
/// Picture).
extension WebKitPage {
    func evaluate(_ script: String) async -> String? {
        // Wrapped so every result comes back as a string (JSON for objects), like Chromium's bridge.
        let wrapped = "(() => { const v = (\(script)); return typeof v === 'string' ? v : JSON.stringify(v ?? null); })()"
        let result = try? await webView.evaluateJavaScript(wrapped)
        return result as? String
    }

    /// WebKit runs a script from the app as a click on the page; `callAsyncJavaScript` awaits its promise. It runs in
    /// Nera's isolated script world, so the page can't swap out what the script calls.
    func evaluateAsUserGesture(_ script: String) async -> String? {
        let result = try? await webView.callAsyncJavaScript("return await (\(script));", contentWorld: .defaultClient)
        return result as? String
    }
}
