// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Downloads

/// SEC-044/045: risky file types need confirmation; finished downloads are quarantined.
@Suite("Download safety")
struct DownloadSafetyTests {
    @Test(arguments: [
        "Installer.pkg", "Nera.dmg", "Tool.app", "run.command", "setup.sh", "profile.mobileconfig", "link.webloc",
        "invoice.pdf.app", "invoice\u{202E}fdp.app", "SETUP.PKG", "game.exe", "macro.scpt",
    ])
    func dangerousTypesNeedConfirmation(_ name: String) {
        guard case .dangerous = DownloadSafety.risk(filename: name, mimeType: nil) else {
            Issue.record("\(name) should be dangerous")
            return
        }
    }

    @Test(arguments: ["report.pdf", "photo.jpg", "archive.zip", "notes.txt", "movie.mp4", "data.csv"])
    func ordinaryFilesAreSafe(_ name: String) {
        #expect(DownloadSafety.risk(filename: name, mimeType: nil) == .safe)
    }

    @Test func dangerousMIMETypesAreFlaggedEvenWithAHarmlessName() {
        if case .safe = DownloadSafety.risk(filename: "download", mimeType: "application/x-apple-diskimage") {
            Issue.record("disk image MIME type should be dangerous")
        }
    }

    @Test func finishedDownloadsGetTheQuarantineAttribute() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "nera-quarantine-\(UUID().uuidString).zip")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(DownloadSafety.quarantineValue(of: file) == nil)
        try DownloadSafety.quarantine(file, date: Date(timeIntervalSince1970: 0x5000_0000))
        #expect(DownloadSafety.quarantineValue(of: file) == "0081;50000000;Nera;")
    }
}
