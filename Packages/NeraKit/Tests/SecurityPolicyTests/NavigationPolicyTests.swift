// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import SecurityPolicy

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    let policy = NavigationPolicy(httpsOnly: true)

    func url(_ s: String) -> URL { URL(string: s)! }

    @Test func httpsIsAllowed() {
        #expect(policy.decide(url("https://example.com"), trigger: .linkClick) == .allow)
    }

    @Test func httpIsUpgradedInHTTPSOnlyMode() {
        #expect(policy.decide(url("http://example.com/a?b=1"), trigger: .userTyped) == .upgrade(url("https://example.com/a?b=1")))
        #expect(policy.decide(url("http://example.com:80/"), trigger: .linkClick) == .upgrade(url("https://example.com/")))
    }

    @Test func loopbackAndExceptionsStayHTTP() {
        #expect(policy.decide(url("http://localhost:3000"), trigger: .userTyped) == .allow)
        #expect(policy.decide(url("http://127.0.0.1"), trigger: .userTyped) == .allow)
        let p = NavigationPolicy(httpsOnly: true, httpExceptions: ["intranet.corp"])
        #expect(p.decide(url("http://intranet.corp"), trigger: .linkClick) == .allow)
    }

    @Test func httpsOnlyOffAllowsHTTP() {
        #expect(NavigationPolicy(httpsOnly: false).decide(url("http://example.com"), trigger: .linkClick) == .allow)
    }

    @Test func subframeHTTPIsNotUpgradedByPolicy() {
        // Mixed content is the engine's job; policy only upgrades top-level navigations.
        #expect(policy.decide(url("http://example.com"), trigger: .script, isMainFrame: false) == .allow)
    }

    @Test(arguments: [NavigationPolicy.Trigger.userTyped, .linkClick, .script, .redirect])
    func javascriptURLsAreAlwaysBlocked(trigger: NavigationPolicy.Trigger) {
        #expect(policy.decide(url("javascript:alert(document.cookie)"), trigger: trigger) == .block(.javascriptURL))
        #expect(policy.decide(url("JaVaScRiPt:alert(1)"), trigger: trigger) == .block(.javascriptURL))
    }

    @Test func dataURLsOnlyTopLevelWhenTyped() {
        let d = url("data:text/html,<h1>hi</h1>")
        #expect(policy.decide(d, trigger: .userTyped) == .allow)
        #expect(policy.decide(d, trigger: .linkClick) == .block(.dataURLTopLevel))
        #expect(policy.decide(d, trigger: .script) == .block(.dataURLTopLevel))
        #expect(policy.decide(d, trigger: .script, isMainFrame: false) == .allow)
    }

    @Test func fileURLsOnlyWhenTyped() {
        let f = url("file:///etc/hosts")
        #expect(policy.decide(f, trigger: .userTyped) == .allow)
        #expect(policy.decide(f, trigger: .linkClick) == .block(.fileURLFromWeb))
        #expect(policy.decide(f, trigger: .redirect) == .block(.fileURLFromWeb))
    }

    @Test func embeddedCredentialsAreBlocked() {
        #expect(policy.decide(url("https://user:pass@example.com"), trigger: .linkClick) == .block(.credentialsInURL))
        #expect(policy.decide(url("https://paypal.com@evil.example"), trigger: .linkClick) == .block(.credentialsInURL))
    }

    @Test func externalSchemesNeedGestureAndConfirmation() {
        #expect(policy.decide(url("mailto:a@b.c"), trigger: .linkClick) == .askToOpenExternally(url("mailto:a@b.c")))
        #expect(policy.decide(url("zoommtg://join?x=1"), trigger: .userTyped) == .askToOpenExternally(url("zoommtg://join?x=1")))
        #expect(policy.decide(url("zoommtg://join?x=1"), trigger: .script) == .block(.unsupportedScheme))
        #expect(policy.decide(url("zoommtg://join?x=1"), trigger: .redirect) == .block(.unsupportedScheme))
    }

    @Test func internalSchemesAllowed() {
        #expect(policy.decide(url("about:blank"), trigger: .script) == .allow)
    }

    @Test func displayURL() {
        #expect(DisplayURL.short(url("https://www.example.com/path?q=1")) == "example.com")
        #expect(DisplayURL.short(url("https://xn--bcher-kva.example/")) == "xn--bcher-kva.example")  // punycode shown, not unicode
        #expect(DisplayURL.isInsecure(url("http://example.com")))
        #expect(!DisplayURL.isInsecure(url("http://localhost:8080")))
        #expect(!DisplayURL.isInsecure(url("https://example.com")))
    }

    @Test func extensionPagesOnlyInNerasOwnPopups() {
        let url = URL(string: "chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/popup.html")!
        for trigger: NavigationPolicy.Trigger in [.userTyped, .linkClick, .script, .redirect] {
            #expect(NavigationPolicy().decide(url, trigger: trigger) == .block(.unsupportedScheme))
        }
        var popup = NavigationPolicy()
        popup.allowsExtensionPages = true
        #expect(popup.decide(url, trigger: .linkClick) == .allow)
    }
}
