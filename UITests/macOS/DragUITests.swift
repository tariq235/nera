// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// Dragging in the sidebar, as in Arc: Favorites reorder, a tab dropped on a Favorite joins the Favorites there, and
/// Spaces reorder in the bottom bar.
@MainActor
final class DragUITests: NeraUITestCase {
    func favorite(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'sidebar.favorite' AND label == %@", title)).firstMatch
    }

    func space(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'sidebar.space' AND label == %@", title)).firstMatch
    }

    func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let met = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
        XCTAssertTrue(met, message)
    }

    func testFavoritesReorderAndTakeTabsDroppedOnThem() {
        openViaCommandBar("data:text/html,<title>Fav A</title>")
        let rowA = sidebarTab("Fav A")
        XCTAssertTrue(rowA.waitForExistence(timeout: 15))
        rowA.rightClick()
        app.menuItems["Move to"].hover()
        app.menuItems["Favorites"].click()
        XCTAssertTrue(favorite("Fav A").waitForExistence(timeout: 5))
        openViaCommandBar("data:text/html,<title>Fav B</title>")
        let rowB = sidebarTab("Fav B")
        XCTAssertTrue(rowB.waitForExistence(timeout: 15))
        rowB.click(forDuration: 0.6, thenDragTo: favorite("Fav A"))
        XCTAssertTrue(favorite("Fav B").waitForExistence(timeout: 5), "the tab dropped on a Favorite didn't join the Favorites")
        waitUntil("it didn't land before the Favorite it was dropped on") {
            self.favorite("Fav B").frame.minX < self.favorite("Fav A").frame.minX
        }
        XCTAssertFalse(sidebarTab("Fav B").exists, "it left the tab list")
        favorite("Fav A").click(forDuration: 0.6, thenDragTo: favorite("Fav B"))
        waitUntil("the Favorites didn't reorder") { self.favorite("Fav A").frame.minX < self.favorite("Fav B").frame.minX }
    }

    func testSpacesReorderByDraggingTheirIcons() {
        let first = app.descendants(matching: .any).matching(identifier: "sidebar.space").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let firstTitle = first.label
        let plus = app.descendants(matching: .any)["sidebar.plusMenu"]
        plus.click()
        app.menuItems["New Space…"].click()
        let name = app.textFields["editSpace.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Dragged")
        app.descendants(matching: .any)["editSpace.done"].click()
        XCTAssertTrue(space("Dragged").waitForExistence(timeout: 5))
        XCTAssertLessThan(space(firstTitle).frame.minX, space("Dragged").frame.minX)
        space("Dragged").click(forDuration: 0.6, thenDragTo: space(firstTitle))
        waitUntil("the Space didn't move") { self.space("Dragged").frame.minX < self.space(firstTitle).frame.minX }
    }
}

extension DragUITests {
    /// A tab dragged out of the window opens in a window of its own; the first window moves to another tab.
    func testATabDraggedOutOfTheWindowOpensInItsOwn() {
        openViaCommandBar("data:text/html,<title>Stay Here</title>")
        XCTAssertTrue(sidebarTab("Stay Here").waitForExistence(timeout: 15))
        openViaCommandBar("data:text/html,<title>Fly Away</title>")
        let row = sidebarTab("Fly Away")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let windows = app.windows.count
        let outside = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 160, dy: 0))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.6, thenDragTo: outside)
        waitUntil("no window opened for the tab") { self.app.windows.count == windows + 1 }
        row.click()  // the tab is still in the shared sidebar; clicking it there shows it in this window again
        XCTAssertTrue(sidebarTab("Stay Here").exists)
    }
}
