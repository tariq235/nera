// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    public import Foundation
    import Import
    public import BrowserData

    /// A password manager Nera can fill passwords with, through its browser extension (Nera never keeps a
    /// password store of its own, SR-032).
    public enum PasswordManager: String, CaseIterable, Identifiable, Sendable {
        /// Apple Passwords, through Apple's iCloud Passwords extension.
        case applePasswords
        /// 1Password.
        case onePassword
        /// Bitwarden.
        case bitwarden

        /// Identity.
        public var id: String { rawValue }

        /// Shown name.
        public var name: String {
            switch self {
            case .applePasswords: "Apple Passwords"
            case .onePassword: "1Password"
            case .bitwarden: "Bitwarden"
            }
        }

        /// Its Chrome Web Store extension.
        public var extensionID: String {
            switch self {
            case .applePasswords: "pejdijmoenmkgeppbflobdenhhabjlaj"  // iCloud Passwords
            case .onePassword: "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
            case .bitwarden: "nngceckbapebfimnlniiiahkandclblb"
            }
        }

        /// Its Mac app, for the icon and to tell whether it's installed.
        public var appPath: String {
            switch self {
            case .applePasswords: "/System/Applications/Passwords.app"
            case .onePassword: "/Applications/1Password.app"
            case .bitwarden: "/Applications/Bitwarden.app"
            }
        }

        /// Whether it's on this Mac.
        public var isOnThisMac: Bool {
            FileManager.default.fileExists(atPath: appPath)
                || (self == .onePassword && FileManager.default.fileExists(atPath: "/Applications/1Password 7.app"))
        }
    }

    /// Saved logins exported for Apple Passwords to import: a private file that's deleted when the user is done.
    public struct PasswordExport: Equatable, Sendable {
        /// The CSV file (readable only by this user).
        public let file: URL
        /// How many logins it holds.
        public let count: Int
        /// The browser they came from.
        public let source: ImportSource
    }

    extension AppModel {
        /// Whether a password manager's extension is installed in Nera.
        public func hasExtension(for manager: PasswordManager) -> Bool {
            extensionStore.extensions.contains { $0.id == manager.extensionID }
        }

        /// Installs a password manager's extension (Nera restarts once to start it).
        public func installPasswordManager(_ manager: PasswordManager) async -> Bool {
            await installFromWebStore([manager.extensionID]) > 0
        }

        /// The folder export files are written to: private to this user and emptied at every launch.
        static var passwordExportFolder: URL {
            FileManager.default.temporaryDirectory.appending(path: "NeraPasswordExport", directoryHint: .isDirectory)
        }

        /// Reads another browser's saved logins (macOS asks to allow access to its key) and writes them to a
        /// private CSV for Apple Passwords' File ▸ Import Passwords. Call ``finishPasswordExport(_:)`` after.
        public func preparePasswordExport(from source: ImportSource) async -> PasswordExport? {
            let logins = await Task.detached { try? ChromiumPasswords.read(from: source) }.value
            guard let logins, !logins.isEmpty else { return nil }
            let folder = Self.passwordExportFolder
            let fm = FileManager.default
            try? fm.removeItem(at: folder)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = folder.appending(path: "\(source.shortCSVName) Passwords.csv")
                let contents = Data(ChromiumPasswords.csv(logins).utf8)
                guard fm.createFile(atPath: file.path, contents: contents, attributes: [.posixPermissions: 0o600]) else { return nil }
                return PasswordExport(file: file, count: logins.count, source: source)
            } catch {
                return nil
            }
        }

        /// Opens Apple Passwords and shows the export file in Finder, ready to pick in File ▸ Import Passwords.
        public func openPasswordsForImport(_ export: PasswordExport) {
            NSWorkspace.shared.open(URL(fileURLWithPath: PasswordManager.applePasswords.appPath))
            NSWorkspace.shared.activateFileViewerSelecting([export.file])
        }

        /// Deletes the export file (the passwords are in Apple Passwords now, or the user changed their mind).
        public func finishPasswordExport(_ export: PasswordExport?) {
            try? FileManager.default.removeItem(at: Self.passwordExportFolder)
        }

        /// Removes an export left behind (Nera quit before the user finished), at launch.
        static func removeStalePasswordExports() {
            try? FileManager.default.removeItem(at: passwordExportFolder)
        }
    }

    extension ImportSource {
        fileprivate var shortCSVName: String {
            switch self {
            case .chrome: "Chrome"
            case .edge: "Edge"
            default: displayName
            }
        }
    }
#endif
