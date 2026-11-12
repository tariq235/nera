// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import XCTest

/// Sound and video, end to end on the default engine: a tab playing sound shows a speaker that mutes it, and a video
/// playing with sound floats out (Picture in Picture) when you leave its tab and goes back when you return.
@MainActor
final class MediaUITests: NeraUITestCase {
    /// A video with sound made in the page (no network, no files): a changing color and a quiet tone, streamed into a
    /// `<video>` the way a call or a camera is.
    static let page =
        "data:text/html,<title>Sound Test</title><canvas id=c width=320 height=180></canvas>"
        + "<video id=v width=320 height=180 playsinline></video><script>"
        + "const a=new AudioContext(),o=a.createOscillator(),g=a.createGain(),d=a.createMediaStreamDestination();"
        + "g.gain.value=0.01;o.connect(g);g.connect(d);o.start();"
        + "const x=c.getContext('2d');let n=0;setInterval(()=>{n=(n+7)&255;x.fillStyle='rgb('+n+',90,'+(255-n)+')';"
        + "x.fillRect(0,0,320,180)},33);"
        + "v.srcObject=new MediaStream([...c.captureStream(30).getVideoTracks(),...d.stream.getAudioTracks()]);v.play();"
        + "</script>"

    /// The test page plays without a click (Debug builds only).
    override var launchEnvironment: [String: String] { ["NERA_AUTOPLAY": "1"] }

    /// The test page's tab once it plays sound.
    func openPlayingPage() -> XCUIElement {
        openViaCommandBar(Self.page)
        let row = sidebarTab("Sound Test")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: row, value: "Playing sound"), "the tab never showed it plays sound")
        return row
    }

    func wait(for element: XCUIElement, value: String, timeout: TimeInterval = 15) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Nera's windows floating above normal ones (Chromium's Picture in Picture window).
    func floatingWindows() -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter {
            ($0[kCGWindowOwnerName as String] as? String) == "Nera" && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
        }.count
    }

    func waitForFloatingWindows(_ count: Int, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if floatingWindows() == count { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// The speaker on the row mutes and unmutes; so does the tab's menu.
    func testPlayingTabShowsSpeakerThatMutes() {
        let row = openPlayingPage()
        // The speaker sits left of the close button (selected row): 8 pt padding, the ✕, 8 pt spacing.
        row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -35, dy: 0)).click()
        XCTAssertTrue(wait(for: row, value: "Muted"), "the speaker didn't mute the tab")
        row.rightClick()
        let unmute = app.menuItems["Unmute"]
        XCTAssertTrue(unmute.waitForExistence(timeout: 5), "the tab menu didn't offer Unmute")
        unmute.click()
        XCTAssertTrue(wait(for: row, value: "Playing sound"), "Unmute didn't bring the sound back")
    }

    /// Leaving the tab floats its video; coming back puts it back, still playing.
    func testVideoPopsOutWhenLeavingItsTab() {
        let row = openPlayingPage()
        XCTAssertEqual(floatingWindows(), 0)
        openViaCommandBar("data:text/html,<title>Elsewhere</title>")
        XCTAssertTrue(sidebarTab("Elsewhere").waitForExistence(timeout: 15))
        XCTAssertTrue(waitForFloatingWindows(1), "the video didn't float out")
        row.click()
        XCTAssertTrue(waitForFloatingWindows(0), "the video didn't go back to its tab")
        XCTAssertTrue(wait(for: row, value: "Playing sound", timeout: 5), "the video stopped when it went back")
    }
}
