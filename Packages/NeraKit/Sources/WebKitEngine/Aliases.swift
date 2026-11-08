// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit

// WebKit (macOS 26 / iOS 26 SDK) declares its own `WebPage` type. Inside this adapter the name
// always means Nera's engine contract.
typealias WebPage = EngineKit.WebPage
