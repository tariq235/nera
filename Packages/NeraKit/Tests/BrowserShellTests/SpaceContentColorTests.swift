// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI
import Testing

/// Spaces brought over from Arc with white text keep it in Nera, also while the Mac is in light mode.
@Suite("Space content colors")
struct SpaceContentColorTests {
    func theme(_ tone: ExactColors.TextTone?) -> SpaceTheme {
        var exact = ExactColors(base: RGBA(red: 0.13, green: 0.38, blue: 0.29))
        exact.textOnColor = tone
        return SpaceTheme(hue: 0.44, saturation: 0.65, appearance: .system, exact: exact)
    }

    @Test func arcSpacesWithWhiteContentGetWhiteTextInLightMode() {
        #expect(Theme.contentScheme(for: theme(.white), in: .light) == .dark)
        #expect(Theme.contentScheme(for: theme(.white), in: .dark) == .dark)
    }

    @Test func otherSpacesFollowTheWindow() {
        #expect(Theme.contentScheme(for: theme(.dark), in: .light) == .light)
        #expect(Theme.contentScheme(for: theme(nil), in: .light) == .light)
        #expect(Theme.contentScheme(for: .default, in: .light) == .light)
        #expect(Theme.contentScheme(for: nil, in: .dark) == .dark)
    }
}
