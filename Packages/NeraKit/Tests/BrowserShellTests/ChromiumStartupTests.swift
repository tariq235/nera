// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// First launch: Chromium starts when the welcome finishes, so the welcome never restarts Nera.
@MainActor
@Suite("Chromium startup")
struct ChromiumStartupTests {
    @Test func theWelcomeNeedsNoRestartWhileChromiumWaitsForIt() {
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
        let flow = OnboardingFlow(model: m)
        flow.blockTrackers = true
        m.chromiumWaitsForWelcome = { true }
        #expect(!flow.needsRelaunch, "the blocker loads on Chromium's first start")
        m.chromiumWaitsForWelcome = { false }
        #expect(flow.needsRelaunch == !m.hasBlocker, "with Chromium already running, new extensions need a relaunch")
    }

    @Test func ifChromiumCantStartTheImportedSignInsGoToWebKit() async throws {
        let webKit = FakeEngine(id: "webkit")
        let registry = EngineRegistry([FakeEngine(id: "chromium"), webKit])
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: registry, downloadsDirectory: nil)
        m.followChromiumStartup()
        let profile = try #require(m.state.currentProfile?.id)
        let cookie = WebCookie(
            domain: ".github.com", name: "user_session", value: "x", path: "/", expires: nil, isSecure: true, isHTTPOnly: true,
            sameSite: "Lax")
        m.pendingSignIns = (profile, [cookie])
        NotificationCenter.default.post(name: ChromiumStartup.didFail, object: nil)
        for _ in 0..<20 where webKit.addedCookies[profile] == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(webKit.addedCookies[profile] == [cookie])
        #expect(m.pendingSignIns == nil)
    }

    @Test func onlyCookiesABrowserWillStoreAreCounted() {
        func cookie(_ domain: String, secure: Bool, sameSite: String?) -> WebCookie {
            WebCookie(
                domain: domain, name: "n", value: "v", path: "/", expires: nil, isSecure: secure, isHTTPOnly: false, sameSite: sameSite)
        }
        #expect(AppModel.isStorable(cookie(".github.com", secure: true, sameSite: "None")))
        #expect(!AppModel.isStorable(cookie(".github.com", secure: false, sameSite: "None")), "SameSite=None needs Secure")
        #expect(!AppModel.isStorable(cookie("localhost", secure: true, sameSite: nil)))
        #expect(!AppModel.isStorable(cookie(".", secure: true, sameSite: nil)))
    }
}
