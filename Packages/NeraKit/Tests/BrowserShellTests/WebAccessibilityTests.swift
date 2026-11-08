// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// A11Y-009: Chromium exposes pages to assistive apps only when it starts with accessibility, so Nera remembers
/// when one is in use and offers a restart.
@MainActor
@Suite("Assistive apps", .serialized)
struct WebAccessibilityTests {
    func model() -> AppModel {
        AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
    }

    @Test func aRestartIsNeededOnlyWhenTheRunningChromiumDiffersFromTheSetting() {
        #expect(WebAccessibility.restartNeeded(setting: true, chromium: .withoutAccessibility))
        #expect(WebAccessibility.restartNeeded(setting: false, chromium: .withAccessibility), "turning it off applies on restart")
        #expect(!WebAccessibility.restartNeeded(setting: true, chromium: .withAccessibility))
        #expect(!WebAccessibility.restartNeeded(setting: true, chromium: .notRunning), "not started yet: it starts with the setting")
        #expect(!WebAccessibility.restartNeeded(setting: true, chromium: nil), "no Chromium: WebKit always exposes pages")
    }

    @Test func theSettingShowsWhatTheUserChoseAndWhenItApplies() {
        let previous = UserDefaults.standard.object(forKey: WebAccessibility.defaultsKey)
        defer {
            UserDefaults.standard.set(previous, forKey: WebAccessibility.defaultsKey)
            WebAccessibility.chromiumState = nil
        }
        WebAccessibility.chromiumState = { .withoutAccessibility }
        let m = model()
        m.letsAssistiveAppsReadPages = true
        #expect(m.letsAssistiveAppsReadPages && m.assistiveSettingNeedsRestart)
        #expect(!m.assistive.restartSuggested, "a choice in Settings doesn't raise the banner over the browser")
        WebAccessibility.chromiumState = { .withAccessibility }
        m.letsAssistiveAppsReadPages = false
        #expect(!m.letsAssistiveAppsReadPages, "the toggle shows the choice, not the running state")
        #expect(m.assistiveSettingNeedsRestart)
    }

    @Test func anAssistiveAppAppearingOffersARestart() async throws {
        let m = model()
        m.followAssistiveApps()
        NotificationCenter.default.post(name: WebAccessibility.needsRestart, object: nil)
        for _ in 0..<50 where !m.assistive.restartSuggested { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.assistive.restartSuggested)
        m.assistive.restartSuggested = false  // Not Now
        WebAccessibility.chromiumState = { .withoutAccessibility }
        defer { WebAccessibility.chromiumState = nil }
        let previous = UserDefaults.standard.object(forKey: WebAccessibility.defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: WebAccessibility.defaultsKey) }
        UserDefaults.standard.set(true, forKey: WebAccessibility.defaultsKey)  // what the bridge does
        #expect(m.assistiveSettingNeedsRestart, "Settings still offers the restart after Not Now")
    }
}
