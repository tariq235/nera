// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserData
import Foundation

#if os(macOS)
    import AppKit
#endif

/// Nera's first launch on a Mac that had Lumen (its name before the public release): copies Lumen's data once
/// (`RenameMigration`). Called by the app before the library loads and before Chromium starts.
public enum RenameStartup {
    /// Whether this launch may migrate: a person opening a Release build. Never Debug builds, self-tests, screenshots,
    /// benchmarks or UI tests (they must not touch the user's data or quit their Lumen); `NERA_MIGRATION_TEST=1` allows
    /// it for a deliberate test.
    static var isInteractiveReleaseLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["NERA_MIGRATION_TEST"] == "1" { return true }
        #if DEBUG
            return false
        #else
            let automated = environment.keys.contains { ["NERA_UI_TEST", "NERA_BENCH", "NERA_AUTOPILOT_CHECK"].contains($0) }
            let flags = CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") }
            return !automated && !flags
        #endif
    }

    /// Runs the one-time copy (only for an interactive Release launch: `isInteractiveReleaseLaunch`).
    public static func migrateFromLumen() {
        #if os(macOS)
            guard isInteractiveReleaseLaunch, let bundleID = Bundle.main.bundleIdentifier,
                let oldID = RenameMigration.previousBundleID(of: bundleID),
                let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
                RenameMigration.isDue(bundleID: bundleID, library: library)
            else { return }
            // Lumen still running would keep writing its databases while they're copied: ask it to quit, and wait.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: oldID)
            for lumen in running { lumen.terminate() }
            for _ in 0..<150 where running.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.2) }
            RenameMigration.run(
                bundleID: bundleID, library: library, keychain: SystemMigrationKeychain(),
                oldDefaults: UserDefaults(suiteName: oldID), newDefaults: .standard,
                lumenIsRunning: running.contains { !$0.isTerminated })
        #endif
    }
}
