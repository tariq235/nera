// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Storage

/// The app's crash-loop guard (SEC-054). Read ``isSafeMode`` before starting engines or loading the library;
/// the first read records this launch as in progress. ``AppModel/live(engines:safeMode:)`` marks the launch
/// successful after it has run stably, and a clean quit does too.
public enum LaunchSafety {
    /// Seconds the app must run before a launch counts as successful.
    public static let stableAfter: Duration = .seconds(10)

    /// Test runs (Debug builds only) never enter safe mode and never touch the real launch record.
    /// Benchmark runs (any build) are force-quit between measurements: they never count as crashes either.
    static var isAutomatedRun: Bool {
        if ProcessInfo.processInfo.environment["NERA_BENCH"] == "1" { return true }
        #if DEBUG
            return ProcessInfo.processInfo.environment["NERA_UI_TEST"] != nil || CommandLine.arguments.contains("--engine-self-test")
                || CommandLine.arguments.contains("--demo")
        #else
            return false
        #endif
    }

    static let launchGuard: LaunchGuard? = isAutomatedRun ? nil : .standard()

    /// Whether this launch runs in safe mode. Evaluated once per process.
    public static let isSafeMode: Bool = launchGuard?.beginLaunch() ?? false

    /// The launch succeeded (stable for a while, or a clean quit).
    public static func launchSucceeded() {
        _ = isSafeMode  // make sure the launch was recorded first
        launchGuard?.launchSucceeded()
    }
}
