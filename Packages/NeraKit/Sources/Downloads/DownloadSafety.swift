// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// How risky a download is to open (SEC-044, SEC-045).
public enum DownloadRisk: Equatable, Sendable {
    /// An ordinary document or media file.
    case safe
    /// Can run code or change the system when opened: the user must confirm before it's saved.
    case dangerous(reason: String)
}

/// Download safety rules: risky file types need explicit confirmation, every finished download gets
/// macOS's quarantine attribute (so Gatekeeper checks it before it can run), and Nera never opens a
/// download by itself.
public enum DownloadSafety {
    /// File types that run code, install software, or change settings when opened.
    static let dangerousExtensions: Set<String> = [
        // macOS apps, installers, disk images and plug-ins
        "app", "pkg", "mpkg", "dmg", "iso", "kext", "prefpane", "plugin", "bundle", "osax", "qlgenerator", "saver",
        "dylib", "framework", "mobileconfig", "configprofile",
        // scripts and automation
        "command", "tool", "sh", "zsh", "bash", "csh", "ksh", "fish", "terminal", "workflow", "action", "scpt", "scptd",
        "applescript", "py", "pl", "rb", "php", "jar", "jnlp",
        // shortcut files that can point anywhere
        "webloc", "inetloc", "fileloc", "url", "lnk",
        // Windows executables (harmless on macOS, dangerous if copied elsewhere)
        "exe", "msi", "bat", "cmd", "com", "scr", "ps1", "vbs", "reg",
    ]

    static let dangerousMIMETypes: Set<String> = [
        "application/x-apple-diskimage", "application/vnd.apple.installer+xml", "application/x-msdownload",
        "application/x-sh", "application/x-shellscript", "application/java-archive", "application/x-apple-aspen-config",
    ]

    /// Classifies a download by its (sanitized) filename and MIME type.
    public static func risk(filename: String, mimeType: String?) -> DownloadRisk {
        let name = DownloadPlanner.sanitize(filename).lowercased()
        let ext = (name as NSString).pathExtension
        if dangerousExtensions.contains(ext) {
            return .dangerous(reason: "“.\(ext)” files can run software or change settings on your Mac.")
        }
        if let mime = mimeType?.lowercased(), dangerousMIMETypes.contains(mime) {
            return .dangerous(reason: "This file can run software or change settings on your Mac.")
        }
        return .safe
    }

    /// The extended attribute macOS uses to mark files from the internet.
    public static let quarantineAttribute = "com.apple.quarantine"

    /// Marks a downloaded file as coming from the internet. Gatekeeper then checks it on first open.
    /// Value format: `flags;hex timestamp;agent;` (0081 = downloaded, not yet approved).
    public static func quarantine(_ file: URL, date: Date = Date()) throws {
        let value = String(format: "0081;%08x;Nera;", Int(date.timeIntervalSince1970))
        let result = value.withCString { bytes in
            setxattr(file.path, quarantineAttribute, bytes, strlen(bytes), 0, 0)
        }
        if result != 0 { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path]) }
    }

    /// The quarantine value of a file, if it has one.
    public static func quarantineValue(of file: URL) -> String? {
        let size = getxattr(file.path, quarantineAttribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(file.path, quarantineAttribute, &buffer, size, 0, 0) == size else { return nil }
        return String(decoding: buffer, as: UTF8.self)
    }
}
