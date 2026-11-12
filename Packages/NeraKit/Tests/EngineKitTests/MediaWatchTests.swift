// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import EngineKit

@Suite("Media watcher")
struct MediaWatchTests {
    @Test func aPageIsAudibleWhileAnyFrameIs() {
        var frames = MediaWatch.Frames()
        #expect(!frames.isAudible)
        let started = frames.report(frame: "top", audible: true)
        #expect(started, "the page starts playing")
        let second = frames.report(frame: "video", audible: true)
        #expect(!second, "a second frame changes nothing")
        let topStopped = frames.report(frame: "top", audible: false)
        #expect(!topStopped && frames.isAudible, "another frame still plays")
        let gone = frames.remove(frame: "video")
        #expect(gone && !frames.isAudible, "the last playing frame went away")
        let unknown = frames.remove(frame: "unknown")
        #expect(!unknown)
        _ = frames.report(frame: "top", audible: true)
        let reset = frames.reset()
        #expect(reset && !frames.isAudible, "a new document starts silent")
        let again = frames.reset()
        #expect(!again)
    }

    /// The Chromium renderer helper can't read files, so it carries its own copy of the watcher: the same text.
    @Test func theChromiumHelperRunsTheSameWatcher() throws {
        let header = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Apps/macOS/ChromiumHelper/media_watch.h")
        let text = try String(contentsOf: header, encoding: .utf8)
        let start = try #require(text.range(of: "R\"NERAJS(\n"))
        let end = try #require(text.range(of: "\n)NERAJS\"", range: start.upperBound..<text.endIndex))
        #expect(String(text[start.upperBound..<end.lowerBound]) == MediaWatch.script)
    }

    @Test func theWatcherReportsAndCanMute() {
        let script = MediaWatch.script
        #expect(script.hasPrefix("(function (report) {"))
        #expect(script.contains("setMuted(on)") && script.contains("mutedByNera"), "WebKit mutes through it")
        #expect(script.contains("getAudioTracks"), "calls and cameras count by their audio track")
    }
}
