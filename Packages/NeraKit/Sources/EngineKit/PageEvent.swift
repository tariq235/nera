// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import SecurityPolicy

/// Something that happened in a page. Events are informational: unlike ``PageRequest`` they need no answer.
public enum PageEvent: Equatable, Sendable {
    /// A main-frame navigation started (URL may be the pending one; never shown in the address bar).
    case navigationStarted(URL?)
    /// A main-frame navigation committed; ``PageState/url`` now shows it.
    case navigationCommitted(URL?)
    /// The page finished loading.
    case navigationFinished(URL?)
    /// A main-frame navigation failed.
    case navigationFailed(URL?, NavigationError)
    /// An `http:` navigation was upgraded to `https:` (HTTPS-Only). If the secure load fails, the app offers to
    /// continue over HTTP.
    case upgradedToHTTPS(from: URL)
    /// The navigation policy refused a navigation (typed or page-initiated).
    case navigationBlocked(URL, NavigationPolicy.Reason)
    /// The page's content process exited. The page shows nothing until it's reloaded or recreated.
    case processTerminated(ProcessTerminationReason)
    /// A download changed state.
    case download(DownloadEvent)
    /// The page called `window.close()` (common for OAuth popups). The app decides whether to close the tab.
    case closeRequested
    /// The page entered (`true`) or left HTML full screen, e.g. a video's full-screen button. The app shows the
    /// page alone, filling the screen, until it leaves.
    case fullscreenChanged(Bool)
}

/// Why a navigation failed.
public enum NavigationError: Equatable, Sendable {
    /// Network-level failure (offline, DNS, refused, timed out…).
    case network(code: Int, description: String)
    /// The server's certificate isn't trusted. A ``CertificateErrorRequest`` is sent as well.
    case certificate(host: String, reason: CertificateErrorReason)
    /// The engine isn't available on this build.
    case engineUnavailable
    /// Anything else.
    case other(String)
}

/// Why a page's content process exited.
public enum ProcessTerminationReason: Equatable, Sendable {
    /// It crashed.
    case crashed
    /// The OS killed it to reclaim memory.
    case memoryPressure
    /// Unknown.
    case unknown
}

/// Progress of one download.
public struct DownloadEvent: Equatable, Sendable {
    /// Identifies the download across events (same as ``DownloadRequest/id``).
    public var id: UUID
    /// The new state.
    public var state: State

    /// Download states.
    public enum State: Equatable, Sendable {
        /// Bytes received so far, and the total if known.
        case progress(received: Int64, total: Int64?)
        /// Finished; the file is at this URL.
        case finished(URL)
        /// Failed with a user-facing description.
        case failed(String)
        /// Cancelled (including when no destination was chosen).
        case cancelled
    }

    /// Creates an event.
    public init(id: UUID, state: State) {
        self.id = id
        self.state = state
    }
}
