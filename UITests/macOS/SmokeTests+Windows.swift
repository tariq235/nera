// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// Windows and the command bar: ⌘N, ⌘W, Esc.
extension SmokeTests {
    /// ⌘N opens another browser window with the command bar ready; a page opened there joins the shared sidebar;
    /// ⇧⌘W closes that window and leaves the first one (FEAT-056).
    func testCommandNOpensAnotherBrowserWindow() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.newTab"].waitForExistence(timeout: 10))
        let windows = app.windows.count
        app.typeKey("n", modifierFlags: .command)
        let more = NSPredicate { _, _ in self.app.windows.count == windows + 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: more, object: nil)], timeout: 5)
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the new window opens with the command bar")
        field.typeText("data:text/html,<title>Second Window Page</title>\n")
        XCTAssertTrue(sidebarTab("Second Window Page").waitForExistence(timeout: 15))
        app.typeKey("w", modifierFlags: [.command, .shift])
        let back = NSPredicate { _, _ in self.app.windows.count == windows }
        wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 5)
        XCTAssertTrue(sidebarTab("Second Window Page").exists, "the tab stays in the shared library")
    }

    /// The command bar closes with Esc, and ⌘W closes what's in front: the bar, then the tab, never the
    /// window (FEAT-051, FEAT-052).
    func testEscAndCommandWCloseTheFrontmostThing() {
        openViaCommandBar("data:text/html,<title>Keep Window</title>")
        XCTAssertTrue(sidebarTab("Keep Window").waitForExistence(timeout: 15))
        let field = app.textFields["commandBar.field"]
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3), "Esc closes the command bar")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(field.waitForNonExistence(timeout: 3), "⌘W closes the command bar first")
        XCTAssertTrue(sidebarTab("Keep Window").exists, "…and not the tab")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(sidebarTab("Keep Window").waitForNonExistence(timeout: 5), "then ⌘W closes the tab")
        XCTAssertTrue(app.windows.firstMatch.exists, "the window stays open")
    }

    /// A private window opens with the command bar ready, and ⌘W closes it while it's empty (FEAT-053).
    func testEmptyPrivateWindowClosesWithCommandW() {
        let windows = app.windows.count
        app.typeKey("n", modifierFlags: [.command, .shift])
        let more = NSPredicate { _, _ in self.app.windows.count == windows + 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: more, object: nil)], timeout: 5)
        XCTAssertTrue(app.textFields["commandBar.field"].waitForExistence(timeout: 5), "opens with the command bar")
        app.typeKey("w", modifierFlags: .command)
        let back = NSPredicate { _, _ in self.app.windows.count == windows }
        wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 5)
    }
}
