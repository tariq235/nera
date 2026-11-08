// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// log-check: debug-only (the Debug-only site check prints its results)
public import EngineKit
import Foundation
import SecurityPolicy

/// The real-site smoke check behind `Nera --site-check` (Debug): loads popular sites in a throwaway profile and
/// prints, per site, whether the page committed and finished, its title and load time. Catches blank pages,
/// crashes and endless loads before people try Nera.
@MainActor
public enum SiteCheckRunner {
    /// The sites checked.
    public static let sites = [
        "https://www.google.com", "https://www.youtube.com", "https://github.com", "https://x.com", "https://www.reddit.com",
        "https://www.wikipedia.org", "https://www.amazon.com", "https://www.notion.so", "https://www.figma.com",
        "https://slack.com", "https://mail.google.com", "https://docs.google.com", "https://www.linkedin.com",
        "https://www.netflix.com", "https://open.spotify.com", "https://chatgpt.com", "https://claude.ai",
        "https://www.nytimes.com", "https://stackoverflow.com", "https://www.apple.com",
    ]

    final class Watcher: WebPageDelegate {
        var committed = false, finished = false, failed: String?, crashed = false
        func pageDidChangeState(_ page: any WebPage) {}
        func page(_ page: any WebPage, didEmit event: PageEvent) {
            switch event {
            case .navigationCommitted: committed = true
            case .navigationFinished: finished = true
            case .navigationFailed(_, let error): failed = "\(error)"
            case .processTerminated: crashed = true
            default: break
            }
        }
        func page(_ page: any WebPage, didRequest request: PageRequest) {}  // dropped: safe defaults apply
    }

    /// Loads every site in `engine` and returns how many failed. `show` puts each page in a window.
    public static func run(engine: any BrowserEngine, show: (any WebPage) -> Void, report: (String) -> Void) async -> Int {
        var bad = 0
        for site in sites {
            guard let url = URL(string: site) else { continue }
            let watcher = Watcher()
            let page = engine.makePage(
                PageConfiguration(id: UUID(), storage: .persistent(UUID()), policy: NavigationPolicy()), delegate: watcher)
            show(page)
            let start = Date()
            page.load(url)
            while Date().timeIntervalSince(start) < 25, !watcher.finished, !watcher.crashed {
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .seconds(1))
            let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
            let ok = watcher.committed && !watcher.crashed && !page.state.title.isEmpty
            if !ok { bad += 1 }
            let host = page.state.url?.host() ?? "-"
            let finish = watcher.finished ? "finished" : "still loading"
            let crash = watcher.crashed ? " CRASHED" : ""
            let failure = watcher.failed.map { " failed: \($0)" } ?? ""
            report(
                "site-check: \(ok ? "✔" : "✘") \(site) → \(host) | \(finish) \(seconds)s | \"\(page.state.title.prefix(60))\"\(crash)\(failure)"
            )
            page.close()
        }
        report("site-check: \(sites.count - bad)/\(sites.count) sites loaded")
        return bad
    }
}
