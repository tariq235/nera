// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// The browser windows open when Nera quits come back when it opens again (UI tests otherwise start from one window,
/// so this class turns it on).
@MainActor
final class WindowRestoreUITests: NeraUITestCase {
    override var launchEnvironment: [String: String] { ["NERA_RESTORE_WINDOWS": "1"] }

    func waitForWindows(_ count: Int, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { _, _ in self.app.windows.count == count }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    func testWindowsOpenAtQuitComeBack() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.newTab"].waitForExistence(timeout: 10))
        let windows = app.windows.count
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitForWindows(windows + 1), "⌘N didn't open a window")
        app.typeKey(.escape, modifierFlags: [])  // the new window's command bar
        let frames = Set(app.windows.allElementsBoundByIndex.map { "\($0.frame)" })
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Nera didn't quit")
        app.launch()
        XCTAssertTrue(waitForWindows(windows + 1), "the windows didn't come back")
        sleep(1)
        XCTAssertEqual(Set(app.windows.allElementsBoundByIndex.map { "\($0.frame)" }), frames, "the windows aren't where they were")
        XCTAssertFalse(app.textFields["commandBar.field"].exists, "restored windows open on their page, not the command bar")
        // Closing the extra window before quitting means only one comes back.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForWindows(windows))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.newTab"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertEqual(app.windows.count, windows, "a closed window came back")
    }
}
