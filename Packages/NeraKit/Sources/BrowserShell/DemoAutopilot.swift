// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Debug-only: the welcome autopilot (see DemoMode.swift for the demo library and screenshots).
#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import EngineKit
    import Foundation

    extension DemoMode {
        /// `NERA_UI_TEST=1 Nera --welcome --autopilot <folder>`: walks the whole welcome with this Mac's real
        /// browsers (in memory: nothing is saved, no Mac settings change, nothing installed) and saves each step.
        /// SwiftUI creates a welcome flow on every redraw of its view (only the first is kept): drive only the first.
        nonisolated(unsafe) private static var isAutopilotRunning = false

        static func runAutopilot(_ flow: OnboardingFlow) {
            guard let folder = argument(after: "--autopilot"), ProcessInfo.processInfo.environment["NERA_UI_TEST"] == "1",
                !isAutopilotRunning
            else { return }
            isAutopilotRunning = true
            flow.makeDefault = false
            flow.addToDock = false
            flow.openAtLogin = false
            flow.blockTrackers = false
            // NERA_AUTOPILOT_CHECK=1: also check that Chromium waits for the welcome and starts after it without a
            // restart, with a cookie added before it started (as the sign-in import does). Results: <folder>/check.json.
            let check = ProcessInfo.processInfo.environment["NERA_AUTOPILOT_CHECK"] == "1"
            if check { flow.includeSignIns = false }  // no Keychain access in an automated run
            let waitedForWelcome = ChromiumStartup.waitsForWelcome
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                resizeWindow()
                if check, let profile = flow.model.state.currentProfile {
                    let cookie = WebCookie(
                        domain: "example.com", name: "nera_check", value: "1", path: "/", expires: Date().addingTimeInterval(86400),
                        isSecure: true, isHTTPOnly: false, sameSite: nil)
                    let engine = flow.model.pages.registry.engine(for: profile)
                    Task { _ = await engine.addCookies([cookie], to: profile.id) }  // waits for Chromium, like the import
                }
                var n = 0
                while flow.model.isWelcomePresented, n < 14 {
                    try? await Task.sleep(for: .seconds(2.2))
                    n += 1
                    _ = capture(to: URL(fileURLWithPath: "\(folder)/\(n)-\(flow.step).png"))
                    if flow.step == .source { flow.source = flow.sources.first }
                    if flow.step == .extensions { flow.pickedExtensions = [] }
                    if flow.step == .summary, flow.summary == nil { continue }
                    flow.next()
                }
                try? await Task.sleep(for: .seconds(4))
                _ = capture(to: URL(fileURLWithPath: "\(folder)/\(n + 1)-browser.png"))
                if check, let url = URL(string: "https://example.com/") {
                    flow.model.send(.tab(.open(url, .newTab)))
                    try? await Task.sleep(for: .seconds(1))
                    let page = flow.model.selectedPage
                    var cookie: String?
                    for _ in 0..<30 where cookie == nil {
                        try? await Task.sleep(for: .seconds(1))
                        if page?.state.isLoading == false { cookie = await page?.evaluate("document.cookie") }
                    }
                    let result: [String: Any] = [
                        "waitedForWelcome": waitedForWelcome, "stillWaiting": ChromiumStartup.waitsForWelcome,
                        "pageEngine": page.map { String(describing: type(of: $0)) } ?? "none",
                        "cookieSeenByPage": cookie?.contains("nera_check=1") ?? false, "relaunched": false,
                    ]
                    let json = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    try? json?.write(to: URL(fileURLWithPath: "\(folder)/check.json"))
                    _ = capture(to: URL(fileURLWithPath: "\(folder)/\(n + 2)-after-check.png"))
                }
                exit(0)
            }
        }
    }
#endif
