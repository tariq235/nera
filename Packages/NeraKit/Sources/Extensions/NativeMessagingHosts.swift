// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Native-messaging hosts for password managers (FEAT-027): the system's iCloud Passwords helper and desktop
/// password managers register for Chrome; Nera's Chromium reads hosts from its own data folder, so Nera
/// mirrors the manifests of an allowlist of known hosts there. Nera never stores passwords itself (SR-032).
public enum NativeMessagingHosts {
    /// Hosts Nera mirrors: Apple's iCloud Passwords helper, 1Password, Bitwarden.
    public static let allowed: Set<String> = ["com.apple.passwordmanager", "com.1password.1password", "com.8bit.bitwarden"]

    /// Where Chrome's manifests live (system-wide first, then the user's).
    public static var chromeLocations: [URL] {
        #if os(macOS)
            let home = FileManager.default.homeDirectoryForCurrentUser
            return [
                URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts"),
                home.appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts"),
            ]
        #else
            return []  // no desktop Chrome or native messaging on iOS
        #endif
    }

    /// Copies valid, allowlisted manifests from `sources` into `destination`. Returns the host names mirrored.
    @discardableResult
    public static func mirror(into destination: URL, from sources: [URL] = chromeLocations, allowed: Set<String> = allowed) -> [String] {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var mirrored: [String] = []
        for name in allowed.sorted() {
            for source in sources {
                let file = source.appending(path: "\(name).json")
                guard let data = try? Data(contentsOf: file), data.count < 64 * 1024, isValid(data, name: name) else { continue }
                try? data.write(to: destination.appending(path: "\(name).json"), options: .atomic)
                mirrored.append(name)
                break
            }
        }
        return mirrored
    }

    /// A manifest is mirrored only if it names itself correctly, points to an existing absolute executable over
    /// stdio, and allows specific extension origins.
    static func isValid(_ data: Data, name: String) -> Bool {
        guard let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], m["name"] as? String == name,
            m["type"] as? String == "stdio", let path = m["path"] as? String, path.hasPrefix("/"),
            FileManager.default.isExecutableFile(atPath: path),
            let origins = m["allowed_origins"] as? [String], !origins.isEmpty,
            origins.allSatisfy({ $0.hasPrefix("chrome-extension://") && !$0.contains("*") })
        else { return false }
        return true
    }
}
