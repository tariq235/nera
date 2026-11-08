// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

#if os(macOS)
    import AppKit
    import ServiceManagement

    /// The welcome screen's Mac switches: keep Nera in the Dock and open it at login. Each runs only when the
    /// user ticks it.
    @MainActor
    enum MacIntegration {
        private static let dock = "com.apple.dock" as CFString
        private static let apps = "persistent-apps" as CFString

        /// Whether the Dock keeps an icon for this app.
        static var isInDock: Bool {
            let id = Bundle.main.bundleIdentifier
            let path = Bundle.main.bundleURL.standardizedFileURL.path
            return dockApps.contains { tile in
                let data = tile["tile-data"] as? [String: Any]
                if let id, data?["bundle-identifier"] as? String == id { return true }
                let raw = (data?["file-data"] as? [String: Any])?["_CFURLString"] as? String
                return raw.flatMap(URL.init(string:))?.standardizedFileURL.path == path
            }
        }

        private static var dockApps: [[String: Any]] {
            CFPreferencesCopyAppValue(apps, dock) as? [[String: Any]] ?? []
        }

        /// Adds Nera to the end of the Dock's apps and restarts the Dock so it shows. Only from /Applications,
        /// so a Dock icon never points at a disk image.
        static func addToDock() {
            let url = Bundle.main.bundleURL.standardizedFileURL
            guard !isInDock, url.path.hasPrefix("/Applications/") || url.path.contains("/Applications/") else { return }
            var tiles = dockApps
            tiles.append([
                "tile-type": "file-tile",
                "tile-data": [
                    "bundle-identifier": Bundle.main.bundleIdentifier ?? "",
                    "file-label": "Nera",
                    "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                ] as [String: Any],
            ])
            CFPreferencesSetAppValue(apps, tiles as CFArray, dock)
            CFPreferencesAppSynchronize(dock)
            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            restart.arguments = ["Dock"]
            try? restart.run()
        }

        /// Whether Nera opens at login.
        static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

        /// Turns opening at login on or off (macOS may ask the user to approve it in System Settings).
        static func setOpensAtLogin(_ on: Bool) {
            if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }

        /// The icon of an installed app, by bundle ID.
        static func appIcon(bundleID: String) -> NSImage? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }
#endif
