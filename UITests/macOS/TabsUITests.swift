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

    /// ⌘W, then ⌘Z: the tab comes back (Arc's undo).
    func testUndoBringsBackAClosedTab() {
        openViaCommandBar("data:text/html,<title>Undo Me</title><h1>undo</h1>")
        XCTAssertTrue(sidebarTab("Undo Me").waitForExistence(timeout: 15))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(sidebarTab("Undo Me").waitForNonExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(sidebarTab("Undo Me").waitForExistence(timeout: 5), "⌘Z didn't bring the tab back")
    }

    /// Typing in a page's field, ⌘Z undoes the typing: it doesn't reopen a closed tab.
    func testUndoWhileTypingInAPageLeavesClosedTabsClosed() {
        openViaCommandBar("data:text/html,<title>Closed One</title>")
        XCTAssertTrue(sidebarTab("Closed One").waitForExistence(timeout: 15))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(sidebarTab("Closed One").waitForNonExistence(timeout: 5))
        // The page names itself after what's typed into it, so the test knows the typing reached the field.
        openViaCommandBar(
            "data:text/html,<title>Form</title><input id=f autofocus oninput=\"document.title='Typed '+this.value\" "
                + "style='width:90vw;height:60vh;font-size:40px'>")
        XCTAssertTrue(sidebarTab("Form").waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)).click()
        app.typeText("hello")
        XCTAssertTrue(sidebarTab("Typed hello").waitForExistence(timeout: 5), "the typing didn't reach the page's field")
        app.typeKey("z", modifierFlags: .command)
        sleep(2)
        XCTAssertFalse(sidebarTab("Closed One").exists, "⌘Z in a page's field reopened a closed tab")
    }

    /// Two pinned tabs (⌘D): dragging the lower one onto the upper one puts it first, and it stays pinned.
    func testDraggingReordersPinnedTabs() {
        for title in ["Pin One", "Pin Two"] {
            openViaCommandBar("data:text/html,<title>\(title)</title>")
            XCTAssertTrue(sidebarTab(title).waitForExistence(timeout: 15))
            app.typeKey("d", modifierFlags: .command)  // pin; pinned tabs keep their order (first pinned first)
        }
        let one = sidebarTab("Pin One")
        let two = sidebarTab("Pin Two")
        XCTAssertLessThan(one.frame.minY, two.frame.minY)
        two.click(forDuration: 0.6, thenDragTo: one)
        let moved = NSPredicate { _, _ in self.sidebarTab("Pin Two").frame.minY < self.sidebarTab("Pin One").frame.minY }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 5)
        let newTab = app.descendants(matching: .any)["sidebar.newTab"]
        XCTAssertLessThan(sidebarTab("Pin One").frame.maxY, newTab.frame.minY, "both stay pinned, above New Tab")
    }

    /// A click on the Space's name folds the pinned tabs away (the one you're on stays); another click shows them.
    func testClickingTheSpaceNameFoldsPinnedTabs() {
        openViaCommandBar("data:text/html,<title>Pinned Page</title>")
        XCTAssertTrue(sidebarTab("Pinned Page").waitForExistence(timeout: 15))
        app.typeKey("d", modifierFlags: .command)
        openViaCommandBar("data:text/html,<title>Today Page</title>")
        XCTAssertTrue(sidebarTab("Today Page").waitForExistence(timeout: 15))
        // Every Space's page is laid out side by side (for swiping): the header on screen is the hittable one.
        let headers = app.descendants(matching: .any).matching(identifier: "sidebar.spaceHeader")
        XCTAssertTrue(headers.firstMatch.waitForExistence(timeout: 5))
        guard let header = headers.allElementsBoundByIndex.first(where: \.isHittable) else { return XCTFail("no visible Space header") }
        header.click()
        XCTAssertTrue(sidebarTab("Pinned Page").waitForNonExistence(timeout: 5), "pinned tabs didn't fold away")
        XCTAssertTrue(sidebarTab("Today Page").exists)
        header.click()
        XCTAssertTrue(sidebarTab("Pinned Page").waitForExistence(timeout: 5), "pinned tabs didn't come back")
    }

    /// On one tab, ⌘T another, ⌘W: back on the tab you were on, not the tab next to the new one.
    func testClosingATabReturnsToTheTabYouWereOn() {
        for title in ["Tab A", "Tab B"] {
            openViaCommandBar("data:text/html,<title>\(title)</title>")
            XCTAssertTrue(sidebarTab(title).waitForExistence(timeout: 15))
        }
        sidebarTab("Tab A").click()  // on A; B sits between it and the next new tab
        openViaCommandBar("data:text/html,<title>Tab C</title>")
        XCTAssertTrue(sidebarTab("Tab C").waitForExistence(timeout: 15))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(sidebarTab("Tab C").waitForNonExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let address = (field.value as? String)?.removingPercentEncoding ?? ""
        XCTAssertTrue(address.contains("Tab A"), "⌘W went to \(address), not back to Tab A")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Change Icon…: an emoji takes the site icon's place in the sidebar.
    func testChangeIconPutsAnEmojiOnTheTab() {
        openViaCommandBar("data:text/html,<title>Icon Tab</title>")
        let row = sidebarTab("Icon Tab")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.typeKey("d", modifierFlags: .command)  // Change Icon is offered for pinned tabs and Favorites
        row.rightClick()
        app.menuItems["Change Icon…"].click()
        let rocket = app.buttons["🚀"]
        XCTAssertTrue(rocket.waitForExistence(timeout: 5), "no icon picker")
        let ready = NSPredicate { _, _ in rocket.isHittable }  // the popover finishes appearing
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
        rocket.click()
        XCTAssertTrue(rocket.waitForNonExistence(timeout: 5), "the picker closes")
        // Reopened, it offers the site's icon back: the tab has the emoji now.
        row.rightClick()
        app.menuItems["Change Icon…"].click()
        let reset = app.buttons["Use the Site's Icon"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertTrue(reset.isEnabled, "the tab didn't take the emoji")
        reset.click()
        row.rightClick()
        app.menuItems["Change Icon…"].click()
        XCTAssertFalse(app.buttons["Use the Site's Icon"].isEnabled, "back to the site's icon")
        app.typeKey(.escape, modifierFlags: [])
    }
}
