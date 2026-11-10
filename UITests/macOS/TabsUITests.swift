// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// Tabs end to end: the command bar's completion, and a Favorite's menu.
@MainActor
final class TabsUITests: NeraUITestCase {
    /// Typing the start of a site the bar completes inline, then Return, opens that site, not a search for the
    /// letters typed (FEAT-061). `.invalid` never resolves, so no network is needed.
    func testReturnOpensTheCompletedSite() {
        openViaCommandBar("http://nera-completion.invalid/")
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("nera-comp")
        field.typeText("\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let shown = NSPredicate { _, _ in (field.value as? String)?.contains("nera-completion.invalid") == true }
        wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 5)
        XCTAssertFalse((field.value as? String ?? "").contains("q=nera-comp"), "Return searched instead of opening the site")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A tab becomes a Favorite from its menu (Move to › Favorites); the Favorite's menu has Arc's items, and
    /// Rename… names it.
    func testFavoriteMenuMovesRenamesAndOffersArcsItems() {
        openViaCommandBar("data:text/html,<title>Fav Page</title><h1>fav</h1>")
        let row = sidebarTab("Fav Page")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.rightClick()
        let moveTo = app.menuItems["Move to"]
        XCTAssertTrue(moveTo.waitForExistence(timeout: 5))
        moveTo.hover()
        app.menuItems["Favorites"].click()
        let tile = app.descendants(matching: .any).matching(identifier: "sidebar.favorite").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "the tab became a Favorite")
        tile.rightClick()
        for item in [
            "Copy Link", "Change Icon…", "Rename…", "Customize Page…", "Edit Pinned Page", "Add Split View", "Duplicate", "Close Tab",
            "Remove Favorite",
        ] {
            XCTAssertTrue(app.menuItems[item].waitForExistence(timeout: 3), "missing \(item)")
        }
        app.menuItems["Rename…"].click()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Mail\n")
        tile.rightClick()
        app.menuItems["Remove Favorite"].click()
        XCTAssertTrue(sidebarTab("Mail").waitForExistence(timeout: 5), "removed from Favorites, kept as a tab with its new name")
    }
}
