// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Starts and stops Chromium for the macOS app. Chromium is the macOS default engine (ADR-0006); WebKit is the
// fallback. Escape hatches (diagnostics, a site that breaks in Chromium): NERA_ENGINE=webkit, or
// `defaults write <bundle id> NeraUseWebKit -bool YES`.
import AppKit
import BrowserShell
import ChromiumEngine
import os

@MainActor
enum ChromiumBootstrap {
    static var isEnabled: Bool {
        if LaunchSafety.isSafeMode { return false }  // safe mode runs the WebKit fallback (SEC-054)
        if let forced = ProcessInfo.processInfo.environment["NERA_ENGINE"] { return forced != "webkit" }
        return !UserDefaults.standard.bool(forKey: "NeraUseWebKit")
    }

    /// The backend handed to ChromiumEngine, or nil when Chromium is off (the engine then reports itself
    /// unavailable and WebKit runs).
    static var backend: (any ChromiumBackend)? { isEnabled ? CEFBackend.shared : nil }

    /// CEF needs the NSApplication (NRAChromiumApplication) to exist: called from willFinishLaunching.
    static func startIfEnabled() {
        guard isEnabled else { return }
        // A11Y-009. Before Chromium starts (or if it can't), it will start with the setting: nothing to restart.
        WebAccessibility.chromiumState = {
            guard NRAChromium.isStarted else { return .notRunning }
            return NRAChromium.isAccessibilityOn ? .withAccessibility : .withoutAccessibility
        }
        #if DEBUG
            if EngineSelfTest.isRequested || SiteCheck.isRequested { return }  // they start Chromium themselves
        #endif
        guard ChromiumStartup.welcomeOnThisLaunch else { return startNow() }
        // First launch: start when the welcome finishes, so the extensions it installs load on this first start and
        // no restart is needed. Meanwhile Chromium counts as available; its pages and cookies wait for it.
        ChromiumStartup.waitsForWelcome = true
        welcomeObserver = NotificationCenter.default.addObserver(forName: ChromiumStartup.welcomeFinished, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let observer = welcomeObserver { NotificationCenter.default.removeObserver(observer) }
                welcomeObserver = nil
                startNow()
            }
        }
    }

    /// The listener for the welcome's end (first launch only); removed once it fires.
    private static var welcomeObserver: NSObjectProtocol?

    /// Starts Chromium with the extensions installed right now (ADR-0012: they load into the extensions profile).
    private static func startNow() {
        let extensions = ExtensionStartup.configuration()
        CEFBackend.shared.extensionPaths = extensions.paths
        CEFBackend.shared.extensionsProfile = extensions.profile
        let wasWaiting = ChromiumStartup.waitsForWelcome
        let started = CEFBackend.shared.start()
        ChromiumStartup.waitsForWelcome = false  // only now: until here, pages kept going to Chromium's queue
        if started {
            if wasWaiting { NotificationCenter.default.post(name: ChromiumStartup.didStart, object: nil) }
        } else {
            Logger(subsystem: "dev.nera.browser", category: "chromium").error("Chromium failed to start; using WebKit")
            NotificationCenter.default.post(name: ChromiumStartup.didFail, object: nil)
        }
    }

    static func shutdown() { CEFBackend.shared.shutdown() }
}

/// macOS application delegate: Chromium's lifecycle around the SwiftUI app's.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ChromiumBootstrap.startIfEnabled() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            MainActor.assumeIsolated {
                if EngineSelfTest.isRequested { EngineSelfTest.run() }
                if SiteCheck.isRequested { SiteCheck.run() }
            }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { ChromiumBootstrap.shutdown() }
    }
}
