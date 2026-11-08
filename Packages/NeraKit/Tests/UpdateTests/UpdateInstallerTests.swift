// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import Foundation
    import Testing

    @testable import Update

    /// Installing updates: the code-signature gate, staging from a real disk image, and the swap after quitting.
    @Suite("Update installer")
    struct UpdateInstallerTests {
        func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "update-tests-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        @Test func updatesMustBeSignedBySameTeamAndBundleID() {
            let installed = URL(fileURLWithPath: "/Applications/Nera.app")
            let installer = UpdateInstaller(installedApp: installed, bundleID: "dev.nera.browser", teamID: "TEAM123456")
            let expected = #"anchor apple generic and identifier "dev.nera.browser" and certificate leaf[subject.OU] = "TEAM123456""#
            #expect(installer.requirement == expected)
            #expect(installer.stagingURL.path == "/Applications/.Nera-update.app", "staged next to the app, so the swap is a rename")
            // An Apple app isn't Nera and isn't signed by Nera's team.
            let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
            #expect(throws: UpdateInstaller.Failure.untrustedSignature) { try installer.verify(calculator, expectedBuild: 1) }
        }

        @Test func developmentBuildsHaveNoInstaller() {
            // The test runner isn't a Developer ID–signed app bundle.
            let folder = tempDir()
            let app = folder.appending(path: "Unsigned.app")
            try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            #expect(UpdateInstaller(installedApp: app, bundleID: "dev.nera.browser") == nil)
        }

        @Test func swapWaitsForQuitThenReplacesTheApp() throws {
            let folder = tempDir()
            let app = folder.appending(path: "Nera.app")
            let installer = UpdateInstaller(installedApp: app, bundleID: "dev.nera.browser", teamID: "TEAM")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: app.appending(path: "version"))
            try FileManager.default.createDirectory(at: installer.stagingURL, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: installer.stagingURL.appending(path: "version"))
            let running = Process()  // stands in for the running Nera
            running.executableURL = URL(fileURLWithPath: "/bin/sleep")
            running.arguments = ["0.6"]
            try running.run()
            try installer.installWhenQuit(relaunch: false, pid: running.processIdentifier)
            Thread.sleep(forTimeInterval: 0.3)
            #expect(String(decoding: try Data(contentsOf: app.appending(path: "version")), as: UTF8.self) == "old", "not before quitting")
            running.waitUntilExit()
            // The swap runs in the background: wait (up to 15 s on a busy machine) for it and its cleanup to finish.
            func leftover() -> Bool {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                return FileManager.default.fileExists(atPath: installer.stagingURL.path) || names.contains { $0.hasPrefix(".nera-old") }
            }
            for _ in 0..<150 where leftover() { Thread.sleep(forTimeInterval: 0.1) }
            #expect(String(decoding: try Data(contentsOf: app.appending(path: "version")), as: UTF8.self) == "new")
            #expect(!FileManager.default.fileExists(atPath: installer.stagingURL.path))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".nera-old") }
            #expect(leftovers.isEmpty, "the old version is removed")
        }

        /// End to end with a real notarized disk image, when a maintainer points the test at one:
        /// `NERA_RELEASE_DMG=<path> NERA_RELEASE_TEAM_ID=<team> NERA_RELEASE_BUILD=<n> swift test --filter UpdateInstallerTests`.
        @Test func stagesAndVerifiesARealDiskImage() throws {
            let environment = ProcessInfo.processInfo.environment
            guard let path = environment["NERA_RELEASE_DMG"], let team = environment["NERA_RELEASE_TEAM_ID"],
                let build = environment["NERA_RELEASE_BUILD"].flatMap(Int.init)
            else { return }
            let dmg = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: dmg.path), !Self.isMounted(dmg) else { return }
            let folder = tempDir()
            let app = folder.appending(path: "Nera.app")
            let installer = UpdateInstaller(installedApp: app, bundleID: "dev.nera.browser", teamID: team)
            let staged = try installer.stage(diskImage: dmg, expectedBuild: build)
            #expect(Bundle(url: staged)?.bundleIdentifier == "dev.nera.browser")
            #expect(throws: UpdateInstaller.Failure.unexpectedBuild) { try installer.stage(diskImage: dmg, expectedBuild: 99) }
            let impostor = UpdateInstaller(installedApp: app, bundleID: "dev.nera.browser", teamID: "ABCDE12345")
            #expect(throws: UpdateInstaller.Failure.untrustedSignature) { try impostor.stage(diskImage: dmg, expectedBuild: build) }
        }

        /// Whether a disk image is already open in Finder (it can't be attached a second time then).
        static func isMounted(_ dmg: URL) -> Bool {
            let info = Process()
            info.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            info.arguments = ["info"]
            let out = Pipe()
            info.standardOutput = out
            guard (try? info.run()) != nil else { return false }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            info.waitUntilExit()
            return text.contains(dmg.path)
        }
    }
#endif
