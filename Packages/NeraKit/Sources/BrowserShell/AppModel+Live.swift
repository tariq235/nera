// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
public import EngineKit
import Extensions
import Foundation
import PageLifecycle
import Storage

extension AppModel {
    /// Production wiring. `engines` comes from the app's composition root, most preferred first.
    /// `NERA_UI_TEST=1` uses an in-memory library and a temporary downloads folder, so automated
    /// runs never touch the user's data.
    public static func live(engines: [any BrowserEngine], safeMode: Bool = false) -> AppModel {
        let registry = EngineRegistry(engines)
        #if os(macOS)
            removeStalePasswordExports()  // never leave exported passwords behind
        #endif
        // Benchmarks run like automated tests: a throwaway library, nothing of the user's read or written.
        let environment = ProcessInfo.processInfo.environment
        var isUITest = environment["NERA_UI_TEST"] == "1" || environment["NERA_BENCH"] == "1"
        var persistence: any StatePersisting = isUITest ? InMemoryStore() : ((try? JSONFileStore.standard()) ?? InMemoryStore())
        #if DEBUG && os(macOS)
            if DemoMode.isRequested {  // README screenshots: a throwaway library, nothing on disk
                isUITest = true
                persistence = InMemoryStore(DemoMode.library())
            }
        #endif
        let downloads =
            isUITest
            ? FileManager.default.temporaryDirectory.appending(path: "NeraUITestDownloads", directoryHint: .isDirectory)
            : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloads { try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true) }
        let history = isUITest ? try? HistoryStore(fileURL: nil) : try? HistoryStore.standard()
        history?.prune()
        let favicons = isUITest ? FaviconStore(directory: nil) : FaviconStore.standard()
        let model = AppModel(
            store: .load(persistence: persistence), registry: registry, downloadsDirectory: downloads, history: history, favicons: favicons,
            extensions: isUITest
                ? ExtensionStore(directory: FileManager.default.temporaryDirectory.appending(path: "NeraUITestExtensions")) : .standard())
        // Automated runs skip the welcome screen unless they test it.
        if isUITest, !CommandLine.arguments.contains("--welcome"), !CommandLine.arguments.contains(where: { $0.hasPrefix("welcome") }) {
            model.send(.library(.completeOnboarding))
        }
        #if DEBUG && os(macOS)
            if DemoMode.isRequested { DemoMode.runIfRequested(model) }
        #endif
        #if os(macOS)
            // Chromium starts after this (applicationWillFinishLaunching): its startup profile is the main profile.
            if !isUITest { ExtensionStartup.mainProfileID = model.extensionsProfileID }
            // A first launch starts Chromium when the welcome finishes, so no restart is needed for its extensions.
            ChromiumStartup.welcomeOnThisLaunch = model.isWelcomePresented && !safeMode
            #if DEBUG
                if environment["NERA_CHROMIUM_AT_LAUNCH"] == "1" { ChromiumStartup.welcomeOnThisLaunch = false }
            #endif
            model.followChromiumStartup()
            model.followAssistiveApps()
            // Safe Browsing lists live next to the library; automated runs use a temporary folder, and only when given
            // a key explicitly (NERA_SAFE_BROWSING_KEY), so they never contact Google by default.
            if isUITest {
                if environment["NERA_SAFE_BROWSING_KEY"] != nil {
                    model.configureSafeBrowsing(
                        directory: FileManager.default.temporaryDirectory.appending(path: "NeraUITestSafeBrowsing"))
                }
            } else if let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            {
                let bundleID = Bundle.main.bundleIdentifier ?? "dev.nera.browser"
                model.configureSafeBrowsing(directory: support.appending(path: "\(bundleID)/SafeBrowsing", directoryHint: .isDirectory))
            }
        #endif
        // Benchmarks (scripts/perf/xbench.swift) run a fresh profile like a user who finished the welcome, with links
        // from the harness opening as tabs, and nothing extra at launch (no offers, icon backfill or update check).
        let isBenchmark = ProcessInfo.processInfo.environment["NERA_BENCH"] == "1"
        if isBenchmark {
            model.send(.library(.completeOnboarding))
            model.send(.library(.setExternalLinks(.currentSpace)))
        }
        if safeMode { model.enterSafeMode() }
        #if os(macOS)
            if !isUITest, !isBenchmark, !safeMode, !model.isWelcomePresented { DefaultBrowser.offerOnce(to: model) }
            if !isUITest, !isBenchmark { model.fillMissingIconsFromArc() }
        #endif
        if !isUITest, !isBenchmark { model.checkForUpdates() }
        Task {
            try? await Task.sleep(for: LaunchSafety.stableAfter)
            // When Chromium starts after the welcome, the launch only counts once Chromium has run stably too, so a
            // crash in its first start still leads to safe mode (SEC-054).
            #if os(macOS)
                while ChromiumStartup.waitsForWelcome { try? await Task.sleep(for: .seconds(1)) }
                if ChromiumStartup.welcomeOnThisLaunch { try? await Task.sleep(for: LaunchSafety.stableAfter) }
            #endif
            LaunchSafety.launchSucceeded()
        }
        return model
    }
}
