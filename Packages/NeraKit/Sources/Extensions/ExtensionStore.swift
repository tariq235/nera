// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import Networking

/// An installed Chrome extension (FEAT-029).
public struct InstalledExtension: Codable, Equatable, Identifiable, Sendable {
    /// Chromium extension ID (32 letters a–p).
    public var id: String
    /// Display name (localized from the manifest).
    public var name: String
    /// Version.
    public var version: String
    /// Short description.
    public var summary: String
    /// Whether it loads at the next start.
    public var isEnabled: Bool
    /// Where it came from.
    public var source: Source
    /// API permissions (`storage`, `tabs`, …).
    public var permissions: [String]
    /// Sites it can read and change (`<all_urls>`, `https://*.example.com/*`, …).
    public var hostPermissions: [String]
    /// Its toolbar popup page, relative to the extension root.
    public var popupPath: String?
    /// Its icon (largest ≤ 128 px), relative to the extension root.
    public var iconPath: String?
    /// When it was installed or last updated.
    public var installedAt: Date

    /// Where an extension came from.
    public enum Source: String, Codable, Sendable {
        /// Chrome Web Store (signed by the store).
        case webStore
        /// A CRX file the user chose (developer-signed).
        case file
    }

    /// Limitations of Nera's embedded Chromium the user should know about (ADR-0012).
    public var compatibilityNotes: [String] {
        var notes: [String] = []
        if popupPath != nil, permissions.contains("tabs") || permissions.contains("activeTab") {
            notes.append("Popup actions on the current tab may not work yet; features on the page itself do.")
        }
        if permissions.contains("nativeMessaging") {
            notes.append("Connecting to its desktop app may not work yet.")
        }
        return notes
    }

    /// Whether it can read and change every site.
    public var readsAllSites: Bool {
        hostPermissions.contains { $0 == "<all_urls>" || $0.hasPrefix("*://*/") || $0 == "http://*/*" || $0 == "https://*/*" }
    }
}

/// Why an install failed.
public enum ExtensionInstallError: Error, Equatable, Sendable {
    /// The package didn't verify.
    case invalidPackage(CRX3.Failure)
    /// The archive couldn't be unpacked safely.
    case unpackFailed
    /// `manifest.json` is missing or invalid.
    case badManifest
    /// Only Manifest V3 extensions run in current Chromium.
    case unsupportedManifestVersion(Int)
    /// Not a Chrome Web Store link or extension ID.
    case notAWebStoreLink
    /// The download failed.
    case downloadFailed
}

/// Installed extensions on disk: `Extensions/<id>/<version>/` plus `extensions.json`. Engine-neutral; the Chromium
/// engine loads the enabled folders at start (changes apply after a relaunch).
public final class ExtensionStore: @unchecked Sendable {
    // @unchecked: `registry` is guarded by `lock`.
    /// Root folder.
    public let directory: URL
    private let lock = NSLock()
    private var registry: Registry

    struct Registry: Codable {
        var extensions: [InstalledExtension] = []
        /// The profile whose pages run extensions (Chromium's startup profile).
        var profileID: UUID?
    }

    /// Opens (creating if needed) the store in `directory`.
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "extensions.json")
        registry = (try? JSONDecoder.iso.decode(Registry.self, from: Data(contentsOf: file))) ?? Registry()
    }

    /// `Application Support/<bundle id>/Extensions`.
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.nera.browser") -> ExtensionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ExtensionStore(directory: base.appending(path: "\(bundleID)/Extensions", directoryHint: .isDirectory))
    }

    /// Installed extensions, by name.
    public var extensions: [InstalledExtension] {
        lock.withLock { registry.extensions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    }

    /// The profile extensions run in (nil until chosen; the app uses its first profile).
    public var profileID: UUID? {
        get { lock.withLock { registry.profileID } }
        set {
            lock.withLock { registry.profileID = newValue }
            save()
        }
    }

    /// Folders of the enabled extensions, for the engine to load.
    public var enabledPaths: [String] {
        lock.withLock { registry.extensions.filter(\.isEnabled).map { folder(for: $0).path } }
    }

    /// The installed folder of an extension.
    public func folder(for ext: InstalledExtension) -> URL {
        directory.appending(path: "\(ext.id)/\(ext.version)", directoryHint: .isDirectory)
    }

    /// Installs (or updates) a verified package.
    @discardableResult
    public func install(crx data: Data, from source: InstalledExtension.Source, expectedID: String? = nil) throws -> InstalledExtension {
        let package: CRX3.Package
        do {
            package = try CRX3.verify(data, requireWebStore: source == .webStore, expectedID: expectedID)
        } catch let failure as CRX3.Failure {
            throw ExtensionInstallError.invalidPackage(failure)
        }
        let staging = directory.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Self.unzip(package.archive, into: staging)
        var manifest = try Self.readManifest(in: staging)
        // Keep the Web Store ID: Chromium derives an unpacked extension's ID from the manifest `key`.
        manifest.raw["key"] = package.developerKey.base64EncodedString()
        try JSONSerialization.data(withJSONObject: manifest.raw, options: [.sortedKeys]).write(to: staging.appending(path: "manifest.json"))

        var ext = manifest.installed(id: package.id, source: source)
        let destination = directory.appending(path: "\(ext.id)/\(ext.version)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory.appending(path: ext.id))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: destination)
        lock.withLock {
            if let old = registry.extensions.first(where: { $0.id == ext.id }) { ext.isEnabled = old.isEnabled }
            registry.extensions.removeAll { $0.id == ext.id }
            registry.extensions.append(ext)
        }
        save()
        return ext
    }

    /// Turns an extension on or off (applies after a relaunch).
    public func setEnabled(_ id: String, _ enabled: Bool) {
        lock.withLock {
            if let i = registry.extensions.firstIndex(where: { $0.id == id }) { registry.extensions[i].isEnabled = enabled }
        }
        save()
    }

    /// Removes an extension and its files.
    public func remove(_ id: String) {
        lock.withLock { registry.extensions.removeAll { $0.id == id } }
        try? FileManager.default.removeItem(at: directory.appending(path: id))
        save()
    }

    private func save() {
        let data = lock.withLock { try? JSONEncoder.iso.encode(registry) }
        try? data?.write(to: directory.appending(path: "extensions.json"), options: .atomic)
    }

    // MARK: Unpacking

    /// Unpacks a ZIP with the system's `ditto`, then rejects anything that could escape the folder.
    static func unzip(_ archive: Data, into folder: URL) throws {
        let zip = folder.deletingLastPathComponent().appending(path: "\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try archive.write(to: zip)
            #if os(macOS)
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-x", "-k", "--noqtn", zip.path, folder.path]
                try ditto.run()
                ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else { throw ExtensionInstallError.unpackFailed }
            #else
                throw ExtensionInstallError.unpackFailed  // extensions run only in Chromium, on macOS
            #endif
        } catch let error as ExtensionInstallError {
            throw error
        } catch {
            throw ExtensionInstallError.unpackFailed
        }
        // No symlinks (they could point outside the extension), and every path stays inside.
        let root = folder.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let file = walker?.nextObject() as? URL {
            let isLink = (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true
            guard !isLink, file.resolvingSymlinksInPath().path.hasPrefix(root) else { throw ExtensionInstallError.unpackFailed }
        }
    }

    // MARK: Manifest

    struct Manifest {
        var raw: [String: Any]
        let folder: URL

        func installed(id: String, source: InstalledExtension.Source) -> InstalledExtension {
            let action = raw["action"] as? [String: Any]
            let icons = (raw["icons"] as? [String: Any] ?? [:]).compactMap { k, v in Int(k).flatMap { s in (v as? String).map { (s, $0) } }
            }
            let icon = icons.filter { $0.0 <= 128 }.max { $0.0 < $1.0 }?.1 ?? icons.min { $0.0 < $1.0 }?.1
            return InstalledExtension(
                id: id, name: localized(raw["name"] as? String ?? id), version: raw["version"] as? String ?? "0",
                summary: localized(raw["description"] as? String ?? ""), isEnabled: true, source: source,
                permissions: raw["permissions"] as? [String] ?? [], hostPermissions: raw["host_permissions"] as? [String] ?? [],
                popupPath: action?["default_popup"] as? String, iconPath: icon, installedAt: Date())
        }

        /// `__MSG_name__` → the default locale's message.
        func localized(_ text: String) -> String {
            guard text.hasPrefix("__MSG_"), text.hasSuffix("__") else { return text }
            let key = String(text.dropFirst(6).dropLast(2)).lowercased()
            let locale = raw["default_locale"] as? String ?? "en"
            let file = folder.appending(path: "_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: file), let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let entry = messages.first(where: { $0.key.lowercased() == key })?.value as? [String: Any],
                let message = entry["message"] as? String
            else { return text }
            return message
        }
    }

    static func readManifest(in folder: URL) throws -> Manifest {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw ExtensionInstallError.badManifest }
        let version = raw["manifest_version"] as? Int ?? 0
        guard version == 3 else { throw ExtensionInstallError.unsupportedManifestVersion(version) }
        return Manifest(raw: raw, folder: folder)
    }

    // MARK: Chrome Web Store

    /// The extension ID in a Chrome Web Store link (`chromewebstore.google.com/detail/<name>/<id>`) or a bare ID.
    public static func webStoreID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isID: (Substring) -> Bool = { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains($0) } }
        if isID(Substring(text)) { return text }
        guard let url = URL(string: text), let host = url.host(),
            host == "chromewebstore.google.com" || host == "chrome.google.com"
        else { return nil }
        return url.pathComponents.last { isID(Substring($0)) }
    }

    /// Downloads a Chrome Web Store item and installs it if it verifies (store signature required).
    @discardableResult
    public func installFromWebStore(_ input: String, chromiumMajor: Int, client: NeraHTTPClient = NeraHTTPClient()) async throws
        -> InstalledExtension
    {
        guard let id = Self.webStoreID(from: input), let url = Self.webStoreDownloadURL(id: id, chromiumMajor: chromiumMajor) else {
            throw ExtensionInstallError.notAWebStoreLink
        }
        let data: Data
        do {
            let (body, response) = try await client.data(for: URLRequest(url: url))
            guard (response as? HTTPURLResponse)?.statusCode == 200, body.count < 64 * 1024 * 1024 else {
                throw ExtensionInstallError.downloadFailed
            }
            data = body
        } catch let error as ExtensionInstallError {
            throw error
        } catch {
            throw ExtensionInstallError.downloadFailed
        }
        return try install(crx: data, from: .webStore, expectedID: id)
    }

    /// Where Chromium downloads a store item (Google's update service; redirects to googleusercontent.com).
    public static func webStoreDownloadURL(id: String, chromiumMajor: Int) -> URL? {
        URL(
            string:
                "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=\(chromiumMajor).0&acceptformat=crx3&x=id%3D\(id)%26uc"
        )
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()
}
