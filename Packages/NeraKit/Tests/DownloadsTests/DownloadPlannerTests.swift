// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Downloads

@Suite("DownloadPlanner")
struct DownloadPlannerTests {
    @Test(arguments: [
        ("report.pdf", "report.pdf"),
        ("../../.ssh/authorized_keys", "authorized_keys"),
        ("/etc/passwd", "passwd"),
        ("..\\..\\Windows\\evil.exe", "evil.exe"),
        (".zshrc", "zshrc"),
        ("..", "download"),
        ("   ", "download"),
        ("", "download"),
        ("invoice\u{202E}fdp.app", "invoicefdp.app"),
        ("a:b.txt", "a_b.txt"),
        ("line\nbreak.txt", "linebreak.txt"),
    ])
    func sanitizes(input: String, expected: String) {
        #expect(DownloadPlanner.sanitize(input) == expected)
    }

    @Test func longNamesKeepTheirExtensionAndFit() {
        let name = DownloadPlanner.sanitize(String(repeating: "é", count: 300) + ".pdf")
        #expect(name.hasSuffix(".pdf"))
        #expect(name.utf8.count <= DownloadPlanner.maxBytes)
    }

    @Test func neverOverwritesExistingFiles() {
        let dir = URL(fileURLWithPath: "/Downloads")
        let taken: Set<String> = ["/Downloads/a.txt", "/Downloads/a (1).txt", "/Downloads/noext"]
        let planner = DownloadPlanner(directory: dir) { taken.contains($0.path) }
        #expect(planner.destination(for: "a.txt").path == "/Downloads/a (2).txt")
        #expect(planner.destination(for: "noext").path == "/Downloads/noext (1)")
        #expect(planner.destination(for: "b.txt").path == "/Downloads/b.txt")
    }

    @Test func destinationAlwaysStaysInsideTheDirectory() {
        let dir = URL(fileURLWithPath: "/Downloads")
        let planner = DownloadPlanner(directory: dir) { _ in false }
        for evil in ["../x", "/../../x", "a/../../b", "..\\..\\c"] {
            #expect(planner.destination(for: evil).deletingLastPathComponent().path == "/Downloads")
        }
    }
}
