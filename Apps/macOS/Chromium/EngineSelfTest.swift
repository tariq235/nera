// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// log-check: debug-only (prints test results; not compiled into Release)
// Debug-only engine self-test, run by CI and `make conformance`: `Nera --engine-self-test`.
// Runs Nera's shared engine conformance suite against real Chromium (CEF, as embedded in this app) and
// WebKit, writes the reports that generate checklist 005's parity matrix, checks Chromium's security
// configuration (SEC-026, SEC-073), then exits non-zero on any failure. Not compiled into Release builds.
#if DEBUG
    import AppKit
    import ChromiumEngine
    import EngineConformance
    import WebKitEngine

    @MainActor
    enum EngineSelfTest {
        static var isRequested: Bool { CommandLine.arguments.contains("--engine-self-test") }

        static func run() {
            setvbuf(stdout, nil, _IOLBF, 0)  // CI reads this output from a pipe or file
            Task { @MainActor in
                var failures: [String] = []
                // Security conformance: both engines trust the local test server's CA (Debug only).
                if let server = LocalTestServer.shared {
                    NRAChromium.setTestCertificateSPKI(server.validSPKIHash)
                    WebKitEngine.testTrustAnchors = [server.caCertificate]
                } else {
                    failures.append("local test server didn't start")
                }
                if !CEFBackend.shared.start() { failures.append("Chromium didn't start") }
                EngineConformance.showOffscreen = { page in
                    // Like a real tab, the page is in a window (WebKit loads no media for a windowless page).
                    let window = NSWindow(
                        contentRect: NSRect(x: -6000, y: -6000, width: 320, height: 240), styleMask: [.borderless],
                        backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = page.view
                    window.orderFrontRegardless()
                    return { window.close() }
                }

                let chromium = await EngineConformance.report {
                    ChromiumEngine(backend: CEFBackend.shared, webAuthenticator: TestWebAuthenticator.shared)
                }
                let webkit = await EngineConformance.report { WebKitEngine() }
                for (name, report) in [("Chromium", chromium), ("WebKit", webkit)] {
                    do { try ConformanceReportWriter.write(report) } catch { failures.append("\(name): report not written: \(error)") }
                    for result in report.results {
                        switch result.outcome {
                        case .passed, .unsupported: break
                        case .failed(let why): failures.append("\(name) \(result.caseID): \(why)")
                        case .engineUnavailable: failures.append("\(name) \(result.caseID): engine unavailable")
                        }
                    }
                    let passed = report.results.filter { $0.outcome == .passed }.count
                    print("engine-self-test: \(name) \(report.engineVersion): \(passed)/\(report.results.count) passed")
                }

                failures += await engineMoveFailures()

                // SEC-031 / PRV-011: private sessions are memory-only — nothing named after one exists on disk.
                let root = FileManager.default.temporaryDirectory.appending(
                    path: "NeraTestChromium-\(ProcessInfo.processInfo.processIdentifier)")
                let onDisk = (FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]) ?? []
                if onDisk.contains(where: { $0.localizedCaseInsensitiveContains("ephemeral") }) {
                    failures.append("a private session left files in Chromium's profile folder")
                }
                if !onDisk.contains(where: { $0.hasPrefix("Profile-") }) { failures.append("sanity: no persistent profile data found") }

                // SEC-026: no switch that weakens security; Nera's privacy switches are present.
                let switches = Set(NRAChromium.commandLineSwitches())
                let forbidden: Set = [
                    "no-sandbox", "disable-web-security", "ignore-certificate-errors", "disable-site-isolation-trials",
                    "allow-running-insecure-content", "remote-debugging-port", "remote-debugging-pipe", "single-process",
                ]
                let privacy: Set = [
                    "disable-background-networking", "disable-component-update", "disable-domain-reliability", "disable-sync",
                    "no-pings", "disable-client-side-phishing-detection", "metrics-recording-only",
                ]
                if !switches.isDisjoint(with: forbidden) { failures.append("forbidden switches: \(switches.intersection(forbidden))") }
                if !privacy.isSubset(of: switches) { failures.append("missing privacy switches: \(privacy.subtracting(switches))") }

                // SEC-073: Nera's own Keychain item, never the one every Chromium app shares.
                let bundleID = Bundle.main.bundleIdentifier ?? "?"
                if NRAChromium.keychainService != "Nera Safe Storage (\(bundleID))" {
                    failures.append("unexpected Keychain service: \(NRAChromium.keychainService ?? "nil")")
                }

                // Persistent profiles must really live on disk (they once fell back to memory silently, so logins
                // were lost at every quit). The conformance run used several persistent profiles by now.
                let chromiumRoot = URL(fileURLWithPath: CEFBackend.shared.rootPath ?? "/nonexistent")
                let profiles =
                    (try? FileManager.default.contentsOfDirectory(atPath: chromiumRoot.path))?.filter { $0.hasPrefix("Profile-") } ?? []
                let profilesOnDisk = profiles.filter {
                    FileManager.default.fileExists(atPath: chromiumRoot.appending(path: "\($0)/Cookies").path)
                }
                if profilesOnDisk.isEmpty {
                    failures.append("no persistent profile wrote its cookie database to disk (\(profiles.count) profile folders)")
                }

                for failure in failures { print("engine-self-test: ✘ \(failure)") }
                print("engine-self-test: \(failures.isEmpty ? "✔ all checks passed" : "✘ \(failures.count) failure(s)")")
                // Exit without CefShutdown: this is a one-shot test process, and tearing down Chromium with
                // pages still closing only adds a wait.
                exit(failures.isEmpty ? 0 : 1)
            }
        }
        /// Video: Chromium (no H.264) flags the sample, so Nera offers WebKit; WebKit plays it. Tabs moving
        /// between engines take their site's cookies along: Chromium reads them by site.
        static func engineMoveFailures() async -> [String] {
            let chromium = ChromiumEngine(backend: CEFBackend.shared, webAuthenticator: TestWebAuthenticator.shared)
            var failures: [String] = []
            let checks: [(String, String?)] = [
                ("Chromium H.264 sample flagged for WebKit", await EngineConformance.checkVideoSample(on: chromium, expectPlayable: false)),
                ("WebKit H.264 sample plays", await EngineConformance.checkVideoSample(on: WebKitEngine(), expectPlayable: true)),
                ("Chromium reads a site's cookies", await EngineConformance.checkCookiesBySite(on: chromium)),
            ]
            for (name, failure) in checks {
                if let failure { failures.append("\(name): \(failure)") } else { print("engine-self-test: \(name) ✔") }
            }
            return failures
        }
    }
#endif
