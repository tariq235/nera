// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A sidebar section shown open or folded away.
public enum SectionFold: String, Codable, Hashable, Sendable {
    /// Its tabs show.
    case open
    /// Only the selected tab shows.
    case folded
}

/// The icon of a Space.
public enum SpaceIcon: Codable, Hashable, Sendable {
    /// A single emoji, e.g. "💼".
    case emoji(String)
    /// An SF Symbol name, e.g. "house.fill".
    case symbol(String)
}
