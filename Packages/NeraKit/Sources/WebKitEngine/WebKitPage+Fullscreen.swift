// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import WebKit

/// HTML full screen (a video's full-screen button): WebKit puts a placeholder where the view was, moves the view into
/// a full-screen window of its own, and swaps it back when full screen ends.
extension WebKitPage {
    /// WebKit shows HTML full screen in a window of its own, not in Nera's.
    var showsFullscreenInOwnWindow: Bool { true }

    /// The page's own way out (the Fullscreen API), run in Nera's isolated script world: WebKit then takes its normal
    /// exit path and puts the view back where it was. (`closeAllMediaPresentations` leaves it out of Nera's window.)
    func exitFullscreen() {
        webView.evaluateJavaScript("document.exitFullscreen()", in: nil, in: .defaultClient) { _ in }
    }

    /// Reports entering and leaving full screen once WebKit's window has finished moving the view.
    func fullscreenObservation() -> NSKeyValueObservation {
        webView.observe(\.fullscreenState) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                switch webView.fullscreenState {
                case .inFullscreen: self?.emit(.fullscreenChanged(true))
                case .notInFullscreen: self?.emit(.fullscreenChanged(false))
                default: break
                }
            }
        }
    }
}
