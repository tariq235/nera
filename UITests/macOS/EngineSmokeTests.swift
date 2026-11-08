// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// Which engine renders pages: Chromium is the macOS default; `NERA_ENGINE=webkit` selects the WebKit
/// fallback. Real app, no network (data: URLs only), in-memory library (`NERA_UI_TEST=1`). The other smoke
/// tests run on the default engine; dialogs, downloads and the policy are also covered by engine conformance.
@MainActor
class ChromiumSmokeTests: XCTestCase {
    /// `NERA_ENGINE` for this suite; nil = the default engine.
    var engine: String? { nil }
    var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["NERA_UI_TEST"] = "1"
        if let engine { app.launchEnvironment["NERA_ENGINE"] = engine }
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func sidebarTab(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'sidebar.tab' AND label == %@", title))
            .firstMatch
    }

    func openViaCommandBar(_ text: String) {
        // Chromium makes launch slower: wait for Nera's UI, then use its New Tab button (not a keystroke
        // that could arrive before the window is key).
        let newTab = app.buttons["empty.newTab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: 30), "Nera's window did not appear")
        newTab.click()
        let field = app.textFields["commandBar.field"]
        if !field.waitForExistence(timeout: 20) { app.typeKey("t", modifierFlags: .command) }  // CI machines can be slow
        XCTAssertTrue(field.waitForExistence(timeout: 20), "command bar did not open")
        field.typeText(text + "\n")
    }

    /// A11Y-009: a page's text and controls are in the accessibility tree VoiceOver reads (inherited by the WebKit
    /// suite, so both engines run it).
    func testScreenReadersCanReadPages() {
        // Chromium exposes pages only when it starts with the assistive-apps setting (WebKit always does).
        app.terminate()
        app.launchArguments += ["-NeraWebAccessibility", "YES"]
        app.launch()
        openViaCommandBar(
            "data:text/html,<title>Readable Page</title><h1>Nera heading</h1><p>Readable paragraph</p><button>Press me</button>")
        XCTAssertTrue(sidebarTab("Readable Page").waitForExistence(timeout: 45), "the page didn't load")
        let text = "Readable paragraph"
        let paragraph = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text))
        XCTAssertTrue(paragraph.firstMatch.waitForExistence(timeout: 20), "the page's text isn't exposed to screen readers")
        XCTAssertTrue(app.buttons["Press me"].waitForExistence(timeout: 10), "the page's button isn't exposed to screen readers")
    }

    /// The page names the engine that rendered it: Chromium's user agent contains "Chrome/", WebKit's doesn't.
    func testPagesRenderInChromium() {
        guard engine == nil else { return }  // the WebKit subclass has its own check
        let probe = "<script>document.title = /Chrome\\//.test(navigator.userAgent) ? 'Engine Chromium' : 'Engine Other'</script>"
        openViaCommandBar("data:text/html," + probe)
        XCTAssertTrue(sidebarTab("Engine Chromium").waitForExistence(timeout: 45), "the page wasn't rendered by Chromium")
    }
}

/// The WebKit fallback still works when selected.
@MainActor
final class WebKitFallbackSmokeTests: ChromiumSmokeTests {
    override var engine: String? { "webkit" }

    func testWebKitFallbackRendersPages() {
        let probe = "<script>document.title = /Chrome\\//.test(navigator.userAgent) ? 'Engine Chromium' : 'Engine WebKit'</script>"
        openViaCommandBar("data:text/html," + probe)
        XCTAssertTrue(sidebarTab("Engine WebKit").waitForExistence(timeout: 30), "the WebKit fallback didn't render the page")
    }
}
