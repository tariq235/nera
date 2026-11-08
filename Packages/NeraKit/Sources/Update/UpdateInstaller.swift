// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    public import Foundation
    import Security

    /// Installs a verified update (ADR-0011, amended 2026-11-04): mounts the downloaded disk image read-only, checks
    /// that the Nera inside is signed by the same Developer ID team and has the same bundle ID as the running app,
    /// stages a copy next to the running app, and swaps it in once Nera has quit (then reopens it if asked).
    ///
    /// The download itself was already checked (exact length, Ed25519 signature with the key built into the app)
    /// by ``UpdateChecker/download(_:)``. The code-signature check here is the second, independent gate.
    public struct UpdateInstaller: Sendable {
        /// Why an update couldn't be installed.
        public enum Failure: Error, Equatable, Sendable {
            /// This build isn't signed with a Developer ID (development builds never update themselves).
            case unsignedBuild
            /// The disk image couldn't be mounted, or it holds no Nera.
            case unreadableImage
            /// The app inside isn't signed by the same team with the same bundle ID, or its signature is broken.
            case untrustedSignature
            /// The app inside isn't the build the feed announced.
            case unexpectedBuild
            /// The folder Nera is in can't be written (the user updates by hand instead).
            case notWritable
            /// Copying or starting the swap failed.
            case installFailed
        }

        /// The running app's bundle.
        public let installedApp: URL
        /// The running app's bundle ID.
        public let bundleID: String
        /// The running app's Developer ID team.
        public let teamID: String

        /// The installer for the running app, or nil for a build that isn't Developer ID–signed.
        public init?(installedApp: URL = Bundle.main.bundleURL, bundleID: String? = Bundle.main.bundleIdentifier) {
            guard let bundleID, let team = Self.teamID(of: installedApp) else { return nil }
            self.init(installedApp: installedApp, bundleID: bundleID, teamID: team)
        }

        /// An installer for a given app, bundle ID and team (tests).
        public init(installedApp: URL, bundleID: String, teamID: String) {
            self.installedApp = installedApp
            self.bundleID = bundleID
            self.teamID = teamID
        }

        /// Where the next version waits until Nera quits: next to the running app, so the swap is a rename.
        public var stagingURL: URL {
            let name = installedApp.deletingPathExtension().lastPathComponent
            return installedApp.deletingLastPathComponent().appending(path: ".\(name)-update.app")
        }

        /// The code requirement every update must meet: Apple-anchored, this bundle ID, this team.
        var requirement: String {
            "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(teamID)\""
        }

        // MARK: Staging

        /// Mounts `diskImage`, checks the app inside and copies it to ``stagingURL``. Returns the staged app.
        public func stage(diskImage: URL, expectedBuild: Int) throws -> URL {
            let fm = FileManager.default
            guard fm.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) else { throw Failure.notWritable }
            let mount = fm.temporaryDirectory.appending(path: "nera-update-\(UUID().uuidString)")
            try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
            let attach = ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, diskImage.path]
            guard Self.run("/usr/bin/hdiutil", attach) else { throw Failure.unreadableImage }
            defer {
                _ = Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
                try? fm.removeItem(at: mount)
            }
            let apps = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
            guard let app = apps.first(where: { $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == bundleID }) else {
                throw Failure.unreadableImage
            }
            try verify(app, expectedBuild: expectedBuild)
            try? fm.removeItem(at: stagingURL)
            guard Self.run("/usr/bin/ditto", [app.path, stagingURL.path]) else { throw Failure.installFailed }
            do {
                try verify(stagingURL, expectedBuild: expectedBuild)  // the copy, as it will run
            } catch {
                try? fm.removeItem(at: stagingURL)
                throw error
            }
            return stagingURL
        }

        /// Checks an app's code signature (deep, strict) against `requirement` and its build number.
        public func verify(_ app: URL, expectedBuild: Int) throws {
            var code: SecStaticCode?
            var requirementRef: SecRequirement?
            guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
                SecRequirementCreateWithString(requirement as CFString, [], &requirementRef) == errSecSuccess, let requirementRef
            else { throw Failure.untrustedSignature }
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
            guard SecStaticCodeCheckValidity(code, flags, requirementRef) == errSecSuccess else { throw Failure.untrustedSignature }
            let build = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            guard build.flatMap(Int.init) == expectedBuild else { throw Failure.unexpectedBuild }
        }

        // MARK: Installing

        /// Starts the swap: a small shell script waits for this process to exit, puts the staged app in place of
        /// the running one (restoring the old one if anything fails) and reopens Nera when `relaunch` is set.
        /// The caller quits the app right after.
        public func installWhenQuit(relaunch: Bool, pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
            guard FileManager.default.fileExists(atPath: stagingURL.path) else { throw Failure.installFailed }
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            // Paths go in as arguments, never into the script text.
            swap.arguments = ["-c", Self.swapScript, "nera-update", String(pid), installedApp.path, stagingURL.path, relaunch ? "1" : "0"]
            swap.standardOutput = FileHandle.nullDevice
            swap.standardError = FileHandle.nullDevice
            do { try swap.run() } catch { throw Failure.installFailed }
        }

        /// `$1` pid to wait for, `$2` the installed app, `$3` the staged app, `$4` 1 to reopen.
        static let swapScript = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            old="$(dirname "$2")/.nera-old-$$.app"
            if mv "$2" "$old"; then
              if mv "$3" "$2"; then rm -rf "$old"; else mv "$old" "$2"; fi
            fi
            [ "$4" = 1 ] && /usr/bin/open "$2"
            exit 0
            """

        // MARK: Helpers

        /// The Developer ID team that signed an app, if any.
        static func teamID(of app: URL) -> String? {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                let dictionary = info as? [String: Any]
            else { return nil }
            return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        }

        @discardableResult
        static func run(_ tool: String, _ arguments: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
    }
#endif
