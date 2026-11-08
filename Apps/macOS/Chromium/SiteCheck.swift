// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// log-check: debug-only (prints results; not compiled into Release)
// Debug-only: `Nera --site-check` runs the real-site smoke check (EngineConformance.SiteCheckRunner) on Chromium.
#if DEBUG
    import AppKit
    import ChromiumEngine
    import EngineConformance
    import Foundation

    @MainActor
    enum SiteCheck {
        static var isRequested: Bool { CommandLine.arguments.contains("--site-check") }

        static func run() {
            setvbuf(stdout, nil, _IOLBF, 0)
            Task { @MainActor in
                guard CEFBackend.shared.start() else {
                    print("site-check: ✘ Chromium didn't start")
                    exit(1)
                }
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
                let bad = await SiteCheckRunner.run(
                    engine: ChromiumEngine(backend: CEFBackend.shared),
                    show: { page in
                        page.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 860)
                        window.contentView = page.view
                    },
                    report: { print($0) })
                exit(bad == 0 ? 0 : 1)
            }
        }
    }
#endif
