// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserData
import Foundation
import Testing

@testable import Import

/// Manual probe (not in CI): `NERA_PROBE_BROWSERS=1 swift test --filter LocalBrowsersProbe` prints how many
/// bookmarks and history pages each installed browser yields. Counts only; nothing is stored.
@Suite("Local browsers probe")
struct LocalBrowsersProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NERA_PROBE_BROWSERS"] == "1"))
    func probe() {
        for source in ImportSource.allCases where source.isInstalled && source != .bookmarksFile {
            var bookmarks = "-"
            var history = "-"
            do {
                switch source {
                case .safari: bookmarks = "\(try BrowserImport.safariBookmarks(Data(contentsOf: source.bookmarksFile!)).allLinks.count)"
                case .firefox: bookmarks = "\(try BrowserImport.firefoxBookmarks(at: source.bookmarksFile!).allLinks.count)"
                default:
                    if let f = source.bookmarksFile, FileManager.default.fileExists(atPath: f.path) {
                        bookmarks = "\(try BrowserImport.chromiumBookmarks(Data(contentsOf: f)).allLinks.count)"
                    } else {
                        bookmarks = "no file"
                    }
                }
            } catch { bookmarks = "error \(error)" }
            do {
                switch source {
                case .safari: history = "\(try BrowserImport.safariHistory(at: source.historyFile!).count)"
                case .firefox: history = "\(try BrowserImport.firefoxHistory(at: source.historyFile!).count)"
                default: history = "\(try BrowserImport.chromiumHistory(at: source.historyFile!).count)"
                }
            } catch { history = "error \(error)" }
            print("probe: \(source.displayName): bookmarks \(bookmarks), history \(history)")
        }
    }
}
