// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// A Chrome Web Store extension found in another Chromium browser's profile, offered for install in Nera.
public struct FoundExtension: Equatable, Identifiable, Sendable {
    /// The Web Store ID (also its ID in Nera once installed).
    public var id: String
    /// Its name.
    public var name: String
    /// Whether it was turned on in that browser.
    public var wasEnabled: Bool
    /// Manifest version; current Chromium runs only V3.
    public var manifestVersion: Int
    /// Its largest icon (PNG), when there is one.
    public var icon: Data?

    /// Whether Nera can run it.
    public var isSupported: Bool { manifestVersion >= 3 }

    /// Creates an entry.
    public init(id: String, name: String, wasEnabled: Bool, manifestVersion: Int, icon: Data? = nil) {
        self.id = id
        self.name = name
        self.wasEnabled = wasEnabled
        self.manifestVersion = manifestVersion
        self.icon = icon
    }
}

/// Lists the Web Store extensions installed in a Chromium profile (`<profile>/Extensions/<id>/<version>`).
/// Only reads; built-in and unpacked extensions are left out. All files are untrusted input.
public enum BrowserExtensions {
    /// The extensions in `profile`, enabled ones first, then by name.
    public static func list(inProfile profile: URL) -> [FoundExtension] {
        let fm = FileManager.default
        let settings = extensionSettings(inProfile: profile)
        let ids = (try? fm.contentsOfDirectory(atPath: profile.appending(path: "Extensions").path)) ?? []
        var found: [FoundExtension] = []
        for id in ids where id.count == 32 && id.allSatisfy({ ("a"..."p").contains($0) }) {
            let dir = profile.appending(path: "Extensions/\(id)")
            let versions = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            guard let version = versions.last,
                let data = try? Data(contentsOf: dir.appending(path: "\(version)/manifest.json")), data.count < 2_000_000,
                let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let folder = dir.appending(path: version)
            let setting = settings[id] ?? [:]
            let fromStore =
                (setting["from_webstore"] as? Bool) == true
                || (manifest["update_url"] as? String).flatMap(URL.init(string:))?.host() == "clients2.google.com"
            guard fromStore else { continue }
            let reasons = setting["disable_reasons"] as? [Any] ?? []
            let state = setting["state"] as? Int
            found.append(
                FoundExtension(
                    id: id, name: localizedName(manifest, folder: folder), wasEnabled: reasons.isEmpty && state != 0,
                    manifestVersion: manifest["manifest_version"] as? Int ?? 2, icon: icon(manifest, folder: folder)))
        }
        return found.sorted { ($0.wasEnabled ? 0 : 1, $0.name.lowercased()) < ($1.wasEnabled ? 0 : 1, $1.name.lowercased()) }
    }

    /// `extensions.settings` from Secure Preferences and Preferences (Chromium keeps it in one of the two).
    static func extensionSettings(inProfile profile: URL) -> [String: [String: Any]] {
        var merged: [String: [String: Any]] = [:]
        for name in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: profile.appending(path: name)), data.count < 50_000_000,
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let settings = (root["extensions"] as? [String: Any])?["settings"] as? [String: Any]
            else { continue }
            for (id, value) in settings { if let dict = value as? [String: Any] { merged[id] = dict } }
        }
        return merged
    }

    /// The manifest's name, resolving `__MSG_key__` from the default locale.
    static func localizedName(_ manifest: [String: Any], folder: URL) -> String {
        let raw = manifest["name"] as? String ?? "Extension"
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__") else { return raw }
        let key = String(raw.dropFirst(6).dropLast(2)).lowercased()
        for locale in [manifest["default_locale"] as? String, "en", "en_US"].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: folder.appending(path: "_locales/\(locale)/messages.json")),
                let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for (k, v) in messages where k.lowercased() == key {
                if let message = (v as? [String: Any])?["message"] as? String { return message }
            }
        }
        return raw
    }

    /// The largest PNG icon listed in the manifest (paths stay inside the extension folder).
    static func icon(_ manifest: [String: Any], folder: URL) -> Data? {
        let icons = manifest["icons"] as? [String: Any] ?? [:]
        let best = icons.compactMap { key, value -> (Int, String)? in
            guard let size = Int(key), let path = value as? String else { return nil }
            return (size, path)
        }.max { $0.0 < $1.0 }
        guard let path = best?.1, !path.contains(".."), path.lowercased().hasSuffix(".png") else { return nil }
        let file = folder.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path)
        guard let data = try? Data(contentsOf: file), data.count < 1_000_000 else { return nil }
        return data
    }
}
