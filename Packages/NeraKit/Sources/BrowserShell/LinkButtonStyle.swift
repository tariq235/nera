// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

extension View {
    /// A text-link button on macOS; a borderless button on iOS, which has no link style.
    func linkButtonStyle() -> some View {
        #if os(macOS)
            buttonStyle(.link)
        #else
            buttonStyle(.borderless)
        #endif
    }
}
