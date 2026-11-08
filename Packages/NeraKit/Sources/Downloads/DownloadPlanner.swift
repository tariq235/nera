// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Turns an untrusted, server-suggested filename into a safe destination that never overwrites
/// an existing file (SEC-046).
///
/// Defends against:
/// - **path traversal**: `../../.ssh/authorized_keys`, absolute paths, Windows separators;
/// - **hidden or special files**: leading dots (`.zshrc`), `.` and `..`;
/// - **extension spoofing**: Unicode bidi controls (`invoice\u{202E}fdp.app` displays as `invoiceppa.pdf`);
/// - **control characters** and names longer than the file system allows.
public struct DownloadPlanner: Sendable {
    /// The folder downloads are saved into.
    public let directory: URL
    private let fileExists: @Sendable (URL) -> Bool

    /// Creates a planner.
    /// - Parameters:
    ///   - directory: Destination folder, normally the user's Downloads folder.
    ///   - fileExists: Existence check (injectable for tests).
    public init(directory: URL, fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.directory = directory
        self.fileExists = fileExists
    }

    /// A destination for `suggestedFilename` that doesn't exist yet: `name.ext`, then `name (1).ext`, `name (2).ext`, …
    public func destination(for suggestedFilename: String) -> URL {
        let safe = Self.sanitize(suggestedFilename)
        let ext = (safe as NSString).pathExtension
        let base = (safe as NSString).deletingPathExtension
        var candidate = directory.appending(path: safe, directoryHint: .notDirectory)
        var n = 1
        while fileExists(candidate) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = directory.appending(path: name, directoryHint: .notDirectory)
            n += 1
            if n > 9_999 {  // Pathological: fall back to a unique name.
                candidate = directory.appending(path: "\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")", directoryHint: .notDirectory)
                break
            }
        }
        return candidate
    }

    /// Characters removed because they can disguise a file's real name or extension.
    static let bidiControls: Set<Character> = [
        "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    /// Maximum filename length in UTF-8 bytes (APFS allows 255).
    static let maxBytes = 200

    /// The safe form of an untrusted filename. Never empty, never a path, never hidden.
    public static func sanitize(_ suggested: String, fallback: String = "download") -> String {
        // Keep only the last path component, whatever separator the server used.
        let lastComponent =
            suggested
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .last.map(String.init) ?? ""
        var name = String(
            lastComponent.filter { ch in
                !bidiControls.contains(ch) && !ch.unicodeScalars.contains { $0.properties.generalCategory == .control }
            })
        name = name.replacingOccurrences(of: ":", with: "_")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }  // no hidden files, no "." or ".."
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return fallback }
        return truncate(name)
    }

    /// Shortens the base name (keeping the extension) to fit ``maxBytes``.
    private static func truncate(_ name: String) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let ext = (name as NSString).pathExtension
        var base = (name as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        guard suffix.utf8.count < maxBytes / 2 else { return String(name.prefix(64)) }
        while (base + suffix).utf8.count > maxBytes { base.removeLast() }
        return base + suffix
    }
}
