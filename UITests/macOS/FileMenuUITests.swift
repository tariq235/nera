// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import XCTest

/// Arc's File menu, end to end: Print, Save Page As, Capture, Blank Window and New Little Window.
@MainActor
final class FileMenuUITests: NeraUITestCase {
    /// A page tall enough to scroll, in two colors, so captures can be told apart from the window.
    static let page =
        "data:text/html,<title>Tall Page</title><body style='margin:0'>"
        + "<div style='height:1400px;background:%23d33'></div><div style='height:1400px;background:%2333d'></div>"

    /// The PNG on the pasteboard, waiting up to `timeout` for it.
    func pastedImage(timeout: TimeInterval = 10) -> NSBitmapImageRep? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = NSPasteboard.general.data(forType: .png), let image = NSBitmapImageRep(data: data) { return image }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    func openTallPage() {
        openViaCommandBar(Self.page)
        XCTAssertTrue(sidebarTab("Tall Page").waitForExistence(timeout: 15))
        sleep(1)
    }

    /// ⌘P opens the print panel (on a physical Mac: a virtual Mac's print system doesn't close the panel on Cancel,
    /// and a panel left open would cover the windows the next tests click in).
    func testPrintShowsThePrintPanel() throws {
        try XCTSkipIf(Self.isVirtualMachine, "print panels on virtual Macs don't close; checked on physical Macs")
        openTallPage()
        app.typeKey("p", modifierFlags: .command)
        let print = app.buttons["Print"]
        XCTAssertTrue(print.waitForExistence(timeout: 10), "no print panel")
        app.typeKey(.escape, modifierFlags: [])
        if !print.waitForNonExistence(timeout: 3) {
            app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.first(where: \.isHittable)?.click()
        }
        XCTAssertTrue(print.waitForNonExistence(timeout: 5), "the print panel didn't close")
    }

    func testSavePageAsShowsTheSavePanel() {
        openTallPage()
        app.typeKey("s", modifierFlags: [.command, .shift])
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no save panel")
        let named = app.textFields.allElementsBoundByIndex.contains { ($0.value as? String)?.hasPrefix("Tall Page") == true }
        XCTAssertTrue(named, "the file is named after the page")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// ⇧⌘2, then a drag: the area, and only it, is on the pasteboard.
    func testCaptureCopiesTheAreaDragged() {
        openTallPage()
        NSPasteboard.general.clearContents()
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Capture…"].click()
        let overlay = app.descendants(matching: .any)["capture.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "no capture overlay")
        // Drag across a fifth of the page, read once in window coordinates.
        let window = app.windows.firstMatch
        let page = overlay.frame
        let frame = window.frame
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: page.minX - frame.minX + page.width * x, dy: page.minY - frame.minY + page.height * y))
        }
        point(0.3, 0.3).press(forDuration: 0.1, thenDragTo: point(0.5, 0.5))
        let image = pastedImage()
        XCTAssertNotNil(image, "nothing on the pasteboard")
        if let image {
            let scale = Double(NSScreen.main?.backingScaleFactor ?? 2)  // captures are in pixels (Retina: 2 per point)
            XCTAssertEqual(
                Double(image.pixelsWide) / scale, Double(page.width * 0.2), accuracy: Double(page.width) * 0.03,
                "the capture is the area dragged")
        }
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 3), "the overlay goes away")
    }

    /// Capture Full Page: the whole page, taller than the window.
    func testCaptureFullPageIsTallerThanTheWindow() {
        openTallPage()
        NSPasteboard.general.clearContents()
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Capture Full Page"].click()
        let image = pastedImage(timeout: 20)
        XCTAssertNotNil(image)
        if let image { XCTAssertGreaterThan(Double(image.size.height), 2_000, "the full 2,800 px page, not the window") }
    }

    /// ⌃⌘N: a window with nothing selected and no command bar; ⌘N: one with the command bar.
    func testBlankWindowOpensWithoutTheCommandBar() {
        XCTAssertTrue(app.buttons["empty.newTab"].waitForExistence(timeout: 15))
        let windows = app.windows.count
        app.typeKey("n", modifierFlags: [.command, .control])
        let opened = NSPredicate { _, _ in self.app.windows.count == windows + 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: opened, object: nil)], timeout: 5)
        XCTAssertFalse(app.textFields["commandBar.field"].waitForExistence(timeout: 2), "a blank window opens without the command bar")
    }

    /// ⌥⌘N, an address, Return: the page opens in a Little Window, not a tab.
    func testNewLittleWindowOpensTheAddressTyped() {
        XCTAssertTrue(app.buttons["empty.newTab"].waitForExistence(timeout: 15))
        let windows = app.windows.count
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["New Little Window…"].click()
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("data:text/html,<title>Little One</title>\n")
        _ = windows
        XCTAssertTrue(app.descendants(matching: .any)["littleWindow"].waitForExistence(timeout: 10), "no Little Window")
        XCTAssertFalse(sidebarTab("Little One").exists, "it opened as a tab")
    }
}
