// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers

    /// Default browser status and the system's "make default" flow.
    @MainActor
    public enum DefaultBrowser {
        /// Whether macOS opens web links with this app.
        public static var isDefault: Bool {
            guard let probe = URL(string: "https://example.com"), let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
                return false
            }
            return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        /// Once, on a launch where Nera isn't the default browser: a notice saying where to change it.
        static func offerOnce(to model: AppModel) {
            let key = "NeraOfferedDefaultBrowser"
            guard !UserDefaults.standard.bool(forKey: key), !isDefault else { return }
            UserDefaults.standard.set(true, forKey: key)
            model.notice = "Make Nera your default browser in Settings › General, so links from other apps open here."
        }

        /// Asks macOS to make Nera the default browser. macOS shows its own confirmation; `done` gets the outcome.
        public static func makeDefault(_ done: @escaping @MainActor (Bool) -> Void) {
            let app = Bundle.main.bundleURL
            Task { @MainActor in
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
                    try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https")
                    try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .html)
                } catch {
                    return done(false)  // the user declined, or macOS refused
                }
                done(isDefault)
            }
        }
    }
#endif
