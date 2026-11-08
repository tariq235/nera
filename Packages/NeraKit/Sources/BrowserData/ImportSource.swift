// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Browsers Nera imports from: where their data lives on this Mac.
public enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case chrome, arc, brave, edge, safari, firefox  // naming: import-reference
    /// A bookmarks HTML file exported by any browser.
    case bookmarksFile

    /// Identity.
    public var id: String { rawValue }

    /// Shown name.
    public var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .arc: "Arc"  // naming: import-reference
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .safari: "Safari"
        case .firefox: "Firefox"
        case .bookmarksFile: "Bookmarks HTML File"
        }
    }

    /// Whether it uses Chromium's profile layout (`Bookmarks` JSON, `History` SQLite).
    public var isChromium: Bool { [.chrome, .arc, .brave, .edge].contains(self) }

    #if os(macOS)
        /// The default profile folder (Chromium family, Firefox) or data folder (Safari) on macOS.
        public var dataDirectory: URL? {
            let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
            switch self {
            case .chrome: return support.appending(path: "Google/Chrome/Default")
            case .arc: return support.appending(path: "Arc/User Data/Default")  // naming: import-reference
            case .brave: return support.appending(path: "BraveSoftware/Brave-Browser/Default")
            case .edge: return support.appending(path: "Microsoft Edge/Default")
            case .safari: return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari")
            case .firefox:
                let profiles = support.appending(path: "Firefox/Profiles")
                let dirs =
                    (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: [.contentModificationDateKey]))
                    ?? []
                // The most recently used profile with a places database.
                return
                    dirs
                    .filter { FileManager.default.fileExists(atPath: $0.appending(path: "places.sqlite").path) }
                    .max {
                        let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return a < b
                    }
            case .bookmarksFile: return nil
            }
        }

        /// The bookmarks file to read.
        public var bookmarksFile: URL? {
            switch self {
            case _ where isChromium: dataDirectory?.appending(path: "Bookmarks")
            case .safari: dataDirectory?.appending(path: "Bookmarks.plist")
            case .firefox: dataDirectory?.appending(path: "places.sqlite")
            default: nil
            }
        }

        /// The history file to read.
        public var historyFile: URL? {
            switch self {
            case _ where isChromium: dataDirectory?.appending(path: "History")
            case .safari: dataDirectory?.appending(path: "History.db")
            case .firefox: dataDirectory?.appending(path: "places.sqlite")
            default: nil
            }
        }

        /// Installed on this Mac (its data folder exists). Safari's folder needs Full Disk Access to read, so
        /// Safari files are picked by the user in an open panel instead.
        public var isInstalled: Bool {
            guard let dir = dataDirectory else { return self == .bookmarksFile }
            return FileManager.default.fileExists(atPath: dir.path)
        }
    #endif
}

/// Why an import failed.
public enum BrowserImportError: Error, Equatable, Sendable {
    /// The file isn't in the expected format.
    case unrecognizedFile
    /// The file couldn't be read (missing, or macOS privacy protection).
    case unreadable
}
