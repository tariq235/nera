// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Where Nera's source is (MPL-2.0 §3.2: whoever receives the app is told how to get it). Shown in
/// Settings › Advanced › About; the DMG's notes say the same. The address is the app's `NeraSourceURL`
/// (project.yml), and the release workflow refuses to publish while that repository doesn't exist.
public enum SourceAvailability {
    /// The public repository, from the app's Info.plist (nil in builds without one, such as tests).
    public static var repository: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "NeraSourceURL") as? String).flatMap(URL.init(string:))
    }

    /// One line for About and the DMG.
    public static let notice = "Nera is open source under the Mozilla Public License 2.0."
}
