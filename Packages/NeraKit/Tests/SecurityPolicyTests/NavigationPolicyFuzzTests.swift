// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineTestSupport
import Foundation
import Testing

@testable import SecurityPolicy

/// Navigation policy fuzzing (SEC-067): whatever the URL, pages can never reach dangerous schemes.
@Suite("Navigation policy fuzz")
struct NavigationPolicyFuzzTests {
    @Test func pagesNeverReachDangerousSchemes() {
        let policy = NavigationPolicy()
        let fromPages: [NavigationPolicy.Trigger] = [.script, .redirect, .linkClick]
        for seed in UInt64(0)..<5000 * SeededRandom.scale {
            var rng = SeededRandom(seed: seed)
            guard let url = URL(string: rng.fuzzString()) else { continue }
            let scheme = url.scheme?.lowercased()
            for trigger in fromPages {
                let decision = policy.decide(url, trigger: trigger, isMainFrame: Bool.random(using: &rng))
                if case .allow = decision {
                    #expect(!["javascript", "vbscript", "file"].contains(scheme ?? ""), "seed \(seed): \(trigger) allowed \(url)")
                }
                if case .askToOpenExternally = decision {
                    #expect(trigger == .linkClick, "seed \(seed): \(trigger) may open other apps")
                }
            }
            if case .upgrade(let upgraded) = policy.decide(url, trigger: .userTyped) {
                #expect(upgraded.scheme == "https", "seed \(seed): upgrade to \(upgraded)")
            }
        }
    }
}
