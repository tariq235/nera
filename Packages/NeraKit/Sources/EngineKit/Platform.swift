// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(AppKit)
    public import AppKit
    /// The native view an engine renders into. `NSView` on macOS, `UIView` on iOS.
    /// It is the only platform type in the engine contract.
    public typealias PlatformView = NSView
#else
    public import UIKit
    /// The native view an engine renders into. `NSView` on macOS, `UIView` on iOS.
    /// It is the only platform type in the engine contract.
    public typealias PlatformView = UIView
#endif
