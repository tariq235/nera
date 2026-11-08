// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import PageLifecycle
import SecurityPolicy
import Storage
import TestSupport
import Testing

@testable import BrowserShell

/// Error pages: certificate problems (never bypassable), unreachable sites, and HTTPS-Only's "continue over HTTP".
@MainActor
@Suite("Page errors")
struct PageErrorTests {
    func model() -> (AppModel, FakePage) {
        let m = AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
        m.send(.library(.completeOnboarding))
        m.send(.tab(.open(URL(string: "https://start.example")!, .newTab)))
        let page = m.selectedPage as! FakePage
        return (m, page)
    }

    @Test func failuresMapToWhatTheUserSees() {
        let site = URL(string: "https://bad.example/")
        #expect(LoadFailure(url: site, error: .network(code: -999, description: "cancelled")) == nil, "cancelled loads aren't errors")
        #expect(LoadFailure(url: site, error: .network(code: -3, description: "aborted")) == nil)
        let cert = LoadFailure(url: site, error: .certificate(host: "bad.example", reason: .dateInvalid))
        #expect(cert?.kind == .certificate(.dateInvalid))
        #expect(LoadFailure(url: site, error: .network(code: -105, description: "DNS"))?.kind == .unreachable("DNS"))
        let http = URL(string: "http://bad.example/")!
        let upgraded = LoadFailure(url: site, error: .network(code: -102, description: "refused"), upgradedFrom: http)
        #expect(upgraded?.kind == .secureConnectionUnavailable(httpURL: http))
        let other = URL(string: "https://other.example")
        let elsewhere = LoadFailure(url: other, error: .network(code: -102, description: "x"), upgradedFrom: http)
        #expect(elsewhere?.kind == .unreachable("x"), "an upgrade of another site doesn't count")
    }

    @Test func httpExceptionsAreSharedByEveryCopyOfThePolicy() {
        let policy = NavigationPolicy()
        let copy = policy
        let http = URL(string: "http://old.example/page")!
        #expect(copy.decide(http, trigger: .userTyped) == .upgrade(URL(string: "https://old.example/page")!))
        policy.allowedOverHTTP.insert("OLD.example")
        #expect(copy.decide(http, trigger: .userTyped) == .allow, "a page made earlier sees the choice at once")
        #expect(copy.decide(URL(string: "http://other.example")!, trigger: .userTyped) != .allow)
    }

    @Test func secureConnectionUnavailableOffersHTTPForThatSite() {
        let (m, page) = model()
        let http = URL(string: "http://old.example/")!
        page.simulate(.upgradedToHTTPS(from: http))
        page.simulate(.navigationFailed(URL(string: "https://old.example/"), .network(code: -102, description: "refused")))
        #expect(m.currentLoadFailure?.kind == .secureConnectionUnavailable(httpURL: http))
        m.continueOverHTTP()
        #expect(m.currentLoadFailure == nil)
        #expect(page.loads.last == http, "loads the http address")
        #expect(m.pages.policy.httpExceptions == ["old.example"])
    }

    @Test func aSecureLoadThatNeverAnswersFallsBackToTheChoice() async throws {
        let (m, page) = model()
        m.pages.httpsFallbackDelay = .milliseconds(50)
        let http = URL(string: "http://slow.example/")!
        page.simulate(.upgradedToHTTPS(from: http))
        for _ in 0..<40 where m.currentLoadFailure == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(m.currentLoadFailure?.kind == .secureConnectionUnavailable(httpURL: http))
        // A secure load that starts showing in time isn't interrupted.
        let (m2, page2) = model()
        m2.pages.httpsFallbackDelay = .milliseconds(50)
        page2.simulate(.upgradedToHTTPS(from: URL(string: "http://fast.example/")!))
        page2.simulate(.navigationCommitted(URL(string: "https://fast.example/")))
        try await Task.sleep(for: .milliseconds(200))
        #expect(m2.currentLoadFailure == nil)
    }

    @Test func certificateErrorsOnlyGoBackAndUnreachableSitesRetry() {
        let (m, page) = model()
        let bad = URL(string: "https://expired.example/")!
        page.simulate(.navigationFailed(bad, .certificate(host: "expired.example", reason: .dateInvalid)))
        #expect(m.currentLoadFailure?.kind == .certificate(.dateInvalid))
        let tabs = m.state.spaces[0].today.count
        m.leaveFailedPage()
        #expect(m.state.spaces[0].today.count == tabs - 1, "nothing to go back to: the tab closes")
        let (m2, page2) = model()
        page2.simulate(.navigationFailed(URL(string: "https://down.example/"), .network(code: -105, description: "Not found")))
        m2.retryFailedLoad()
        #expect(page2.loads.last?.absoluteString == "https://down.example/" && m2.currentLoadFailure == nil)
        page2.simulate(.navigationFailed(URL(string: "https://down.example/"), .network(code: -105, description: "Not found")))
        page2.simulate(.navigationCommitted(URL(string: "https://down.example/")))
        #expect(m2.currentLoadFailure == nil, "a page that loads clears the error")
    }
}
