// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import EngineConformance
import EngineKit
import Foundation
import Testing
import WebKit

@testable import WebKitEngine

/// Runs the shared engine conformance suite against real WebKit (no network).
@MainActor
@Suite("WebKit conformance")
struct WebKitConformanceTests {
    /// The security conformance cases need WebKit to trust the local test server's CA (Debug-only hook).
    init() {
        WebKitEngine.testTrustAnchors = LocalTestServer.shared.map { [$0.caCertificate] } ?? []
        EngineConformance.showOffscreen = { page in
            // C21: WebKit loads no media for a page that isn't in a window, as every tab is in Nera.
            let window = NSWindow(
                contentRect: NSRect(x: -6000, y: -6000, width: 320, height: 240), styleMask: [.borderless], backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = page.view
            window.orderFrontRegardless()
            return { window.close() }
        }
    }

    @Test(arguments: EngineConformance.cases)
    func conformance(_ testCase: ConformanceCase) async {
        let result = await EngineConformance.run(testCase) { WebKitEngine() }
        switch result.outcome {
        case .passed, .unsupported: break
        case .failed(let why): Issue.record("\(testCase.id) failed: \(why)")
        case .engineUnavailable: Issue.record("WebKit must always be available")
        }
    }

    /// Writes `build/conformance/webkit.json` for `scripts/ci/render-engine-matrix.py`.
    @Test func writesConformanceReport() async throws {
        let report = await EngineConformance.report { WebKitEngine() }
        #expect(report.results.count == EngineConformance.cases.count)
        try ConformanceReportWriter.write(report)
    }
}

@MainActor
@Suite("WebKit adapter internals")
struct WebKitAdapterTests {
    @Test func serverTrustIsAlwaysLeftToTheSystem() {
        // SR-002: Nera never overrides certificate validation.
        #expect(WebKitPage.challengeHandling(for: NSURLAuthenticationMethodServerTrust) == .systemDefault)
        #expect(WebKitPage.challengeHandling(for: NSURLAuthenticationMethodClientCertificate) == .systemDefault)
        #expect(WebKitPage.challengeHandling(for: NSURLAuthenticationMethodHTTPBasic) == .askUser)
        #expect(WebKitPage.challengeHandling(for: NSURLAuthenticationMethodHTTPDigest) == .askUser)
    }

    @Test func certificateFailuresAreRecognized() {
        func err(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }
        #expect(WebKitPage.certificateReason(for: err(NSURLErrorServerCertificateHasBadDate)) == .dateInvalid)
        #expect(WebKitPage.certificateReason(for: err(NSURLErrorServerCertificateNotYetValid)) == .dateInvalid)
        #expect(WebKitPage.certificateReason(for: err(NSURLErrorServerCertificateUntrusted)) == .untrusted)
        #expect(WebKitPage.certificateReason(for: err(NSURLErrorServerCertificateHasUnknownRoot)) == .untrusted)
        #expect(WebKitPage.certificateReason(for: err(NSURLErrorNotConnectedToInternet)) == nil)
    }

    @Test func certificateErrorsAreNeverBypassableOnWebKit() {
        #expect(!WebKitEngine().capabilities.contains(.certificateErrorBypass))
    }

    @Test func cancellationsAreNotReportedAsFailures() {
        #expect(WebKitPage.isIgnorable(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!WebKitPage.isIgnorable(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
    }

    @Test func privateSessionStoreIsDroppedWhenItsLastPageCloses() {
        let engine = WebKitEngine()
        let session = UUID()
        let delegate = NullDelegate()
        let a = engine.makePage(PageConfiguration(id: UUID(), storage: .ephemeral(session), policy: .init()), delegate: delegate)
        let b = engine.makePage(PageConfiguration(id: UUID(), storage: .ephemeral(session), policy: .init()), delegate: delegate)
        #expect(engine.ephemeralSessionCount == 1)
        a.close()
        #expect(engine.ephemeralSessionCount == 1)
        b.close()
        #expect(engine.ephemeralSessionCount == 0)
    }

    /// Closing a tab that's playing sound silences it at once: WebKit's media process would otherwise play on for
    /// seconds after the view is gone.
    @Test func closingAPagePausesItsMediaAtOnce() async throws {
        let server = try #require(LocalTestServer.shared)
        setenv("NERA_AUTOPLAY", "1", 1)
        defer { unsetenv("NERA_AUTOPLAY") }
        let page = try #require(
            WebKitEngine().makePage(PageConfiguration(id: UUID(), storage: .ephemeral(UUID()), policy: .init()), delegate: NullDelegate())
                as? WebKitPage)
        let window = NSWindow(
            contentRect: NSRect(x: -6000, y: -6000, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.view
        window.orderFrontRegardless()
        defer { window.close() }
        page.load(server.url("/audio"))
        var state = WKMediaPlaybackState.none
        for _ in 0..<100 where state != .playing {
            try await Task.sleep(for: .milliseconds(100))
            state = await page.webView.requestMediaPlaybackState()
        }
        try #require(state == .playing, "the tone never started")
        page.close()
        let after = await page.webView.requestMediaPlaybackState()
        #expect(after != .playing, "still playing after close: \(after.rawValue)")
    }

    /// WebKit calls delegates by Objective-C selector. A Swift method whose name is slightly off still
    /// compiles but is silently never called (this happened to the media-permission handler). Prove
    /// every callback the contract relies on is really wired, by its exact selector.
    @Test(arguments: [
        "webView:decidePolicyForNavigationAction:decisionHandler:",
        "webView:decidePolicyForNavigationResponse:decisionHandler:",
        "webView:navigationAction:didBecomeDownload:",
        "webView:navigationResponse:didBecomeDownload:",
        "webView:didStartProvisionalNavigation:",
        "webView:didCommitNavigation:",
        "webView:didFinishNavigation:",
        "webView:didFailProvisionalNavigation:withError:",
        "webView:didFailNavigation:withError:",
        "webView:didReceiveAuthenticationChallenge:completionHandler:",
        "webViewWebContentProcessDidTerminate:",
        "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:",
        "webViewDidClose:",
        "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
        "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:",
        "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
        "downloadDidFinish:",
        "download:didFailWithError:resumeData:",
    ])
    func delegateCallbackIsWired(_ selector: String) throws {
        let page = WebKitEngine().makePage(
            PageConfiguration(id: UUID(), storage: .ephemeral(UUID()), policy: .init()), delegate: NullDelegate())
        let object = try #require(page as? NSObject)
        #expect(object.responds(to: NSSelectorFromString(selector)), "WebKit would never call \(selector)")
        page.close()
    }

    #if os(macOS)
        @Test func fileChooserCallbackIsWired() throws {
            let page = WebKitEngine().makePage(
                PageConfiguration(id: UUID(), storage: .ephemeral(UUID()), policy: .init()), delegate: NullDelegate())
            let object = try #require(page as? NSObject)
            #expect(object.responds(to: NSSelectorFromString("webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:")))
            page.close()
        }
    #endif

    @Test func descriptorIdentifiesWebKit() {
        let d = WebKitEngine().descriptor
        #expect(d.id == "webkit" && d.isAvailable && !d.version.isEmpty)
    }
}

@MainActor
final class NullDelegate: WebPageDelegate {
    func pageDidChangeState(_ page: any EngineKit.WebPage) {}
    func page(_ page: any EngineKit.WebPage, didEmit event: PageEvent) {}
    func page(_ page: any EngineKit.WebPage, didRequest request: PageRequest) {}
}

/// WebKit favicon discovery and decoding.
@Suite("WebKit favicons")
struct WebKitFaviconTests {
    @Test func candidatesPreferRasterIconsAndFallBackToFaviconICO() {
        let page = URL(string: "https://site.example:8443/a/b")!
        let links = [
            ["https://site.example/icon.svg", "icon", "", "image/svg+xml"],
            ["https://site.example/touch.png", "apple-touch-icon", "180x180", ""],
            ["https://site.example/i32.png", "icon", "32x32", "image/png"],
            ["javascript:alert(1)", "icon", "", ""],
        ]
        let urls = FaviconLoader.candidates(links: links, pageURL: page).map(\.absoluteString)
        #expect(urls == ["https://site.example/i32.png", "https://site.example/touch.png", "https://site.example:8443/favicon.ico"])
    }

    @Test func imagesAreNormalizedToSmallPNGsAndJunkIsRejected() throws {
        let big = try #require(Data(base64Encoded: LocalTestServer.iconPNG))
        let png = try #require(FaviconLoader.normalize(big))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(FaviconLoader.normalize(Data("<html>not an image</html>".utf8)) == nil)
    }
}

/// Moving a tab between engines: a site's cookies can be read and written per storage scope.
@MainActor
@Suite("WebKit cookies")
struct WebKitCookieTests {
    func cookie(_ domain: String, _ name: String) -> WebCookie {
        WebCookie(domain: domain, name: name, value: "v", path: "/", expires: nil, isSecure: true, isHTTPOnly: true, sameSite: "Lax")
    }

    @Test func aPrivateSessionsCookiesAreReadBySite() async {
        let engine = WebKitEngine()
        let scope = StorageScope.ephemeral(UUID())
        #expect(await engine.cookies(forSite: "spotify.com", in: scope).isEmpty, "no session yet: nothing, and none made")
        #expect(engine.ephemeralSessionCount == 0)
        // A private tab moving here: its cookies arrive before its page.
        let added = await engine.addCookies(
            [cookie(".spotify.com", "sp_dc"), cookie("open.spotify.com", "sp_t"), cookie(".notspotify.com", "x")], in: scope)
        #expect(added == 3)
        let read = await engine.cookies(forSite: "spotify.com", in: scope)
        #expect(Set(read.map(\.name)) == ["sp_dc", "sp_t"])
        #expect(read.allSatisfy { $0.isHTTPOnly && $0.isSecure })
        await engine.removeWebsiteData(for: scope)
    }
}
