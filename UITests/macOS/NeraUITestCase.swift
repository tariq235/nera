// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

/// What every UI test class shares: Nera launched with an in-memory library (`NERA_UI_TEST=1`), so tests never touch
/// user data, and helpers.
@MainActor
class NeraUITestCase: XCTestCase {
    /// GitHub's runners are virtual Macs: some system panels (print) behave differently there.
    static var isVirtualMachine: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0)
        return value == 1
    }

    var app = XCUIApplication()

    /// More environment for Nera, set by a test class before launch.
    var launchEnvironment: [String: String] { [:] }

    override func setUp() async throws {
        // Stopping at the first failure starts once Nera runs: a failed first launch that's retried must not stop
        // the test (XCTest would skip its body and still count it as passed).
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["NERA_UI_TEST"] = "1"
        app.launchEnvironment.merge(launchEnvironment) { _, new in new }
        // On CI virtual machines the first launch occasionally fails ("does not have a process ID"); one retry.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("first launch on a CI virtual machine", options: options) { app.launch() }
        if app.state != .runningForeground {
            app.launch()
        }
        XCTAssertEqual(app.state, .runningForeground, "Nera didn't launch")
        continueAfterFailure = false
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
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBar.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "command bar did not open")
        field.typeText(text + "\n")
    }
}
