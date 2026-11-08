// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

#if os(macOS)
    import Security
#endif

/// The one Keychain item the migration copies (a fake in tests).
public protocol MigrationKeychain {
    /// Whether the item exists (never asks the user).
    func exists(service: String, account: String) -> Bool
    /// The item's secret, or nil when there's none or it can't be read (the user said no).
    func password(service: String, account: String) -> Data?
    /// Stores the item, replacing its secret if it exists; false if it couldn't.
    func store(_ password: Data, service: String, account: String) -> Bool
}

/// Nera was called Lumen before its public release. On Nera's very first run on a Mac that has Lumen's data, that
/// data is copied over once: the data folder (library, history, icons, extensions, Chromium profiles), WebKit's
/// website data, the Keychain item that encrypts Chromium's cookies and saved passwords, and the settings. Lumen's
/// own data is left as it is, so going back is always possible.
///
/// Rules: it runs only if Nera has no data yet (it never replaces anything Nera made); it waits while Lumen is still
/// running; it never copies sign-ins it can't decrypt; and a marker in Lumen's folder makes it happen once, even if
/// Nera is later deleted and installed again.
public enum RenameMigration {
    /// What happened.
    public struct Outcome: Equatable, Sendable {
        /// The data folder was copied.
        public var copiedData = false
        /// The Chromium cookie key was copied.
        public var copiedKey = false
        /// How many settings were copied.
        public var copiedSettings = 0
        /// Lumen was still running: nothing copied yet, tried again at the next launch.
        public var deferred = false
        /// Lumen's cookie key exists but couldn't be read: its Chromium profiles weren't copied (they'd be unreadable).
        public var skippedSignIns = false
    }

    /// Lumen's bundle ID for a Nera bundle ID (`dev.nera.browser` → `dev.lumen.browser`, also `.test`, `.debug`).
    public static func previousBundleID(of bundleID: String) -> String? {
        bundleID.hasPrefix("dev.nera.browser") ? "dev.lumen.browser" + bundleID.dropFirst("dev.nera.browser".count) : nil
    }

    /// The Keychain item Chromium uses for a bundle ID (service, account), as the Chromium bridge names it.
    public static func cookieKeyItem(product: String, bundleID: String) -> (service: String, account: String) {
        ("\(product) Safe Storage (\(bundleID))", product)
    }

    /// Marks Lumen's folder once its data was copied to Nera.
    static let doneMarker = ".copied-to-nera"
    /// Marks Nera's folder while the migration still has to happen (Lumen was running, or a copy failed).
    static let pendingMarker = ".awaiting-lumen"
    /// Settings that describe Lumen itself, not the user's choices.
    static let settingsNotCopied: Set = ["LumenOfferedDefaultBrowser", "LumenLastUpdateCheck"]

    /// Whether the migration still has to happen (cheap; checked before asking Lumen to quit).
    public static func isDue(bundleID: String, library: URL) -> Bool {
        let fm = FileManager.default
        guard let oldID = previousBundleID(of: bundleID), let oldFolder = lumenFolder(oldID, library: library),
            !fm.fileExists(atPath: oldFolder.appending(path: doneMarker).path)
        else { return false }
        let newFolder = library.appending(path: "Application Support/\(bundleID)")
        return !fm.fileExists(atPath: newFolder.path) || fm.fileExists(atPath: newFolder.appending(path: pendingMarker).path)
    }

    /// Runs the migration if it's due. `library` is `~/Library`.
    @discardableResult
    public static func run(
        bundleID: String, library: URL, keychain: any MigrationKeychain, oldDefaults: UserDefaults?, newDefaults: UserDefaults,
        lumenIsRunning: Bool = false
    ) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        guard let oldID = previousBundleID(of: bundleID), let oldFolder = lumenFolder(oldID, library: library),
            !fm.fileExists(atPath: oldFolder.appending(path: doneMarker).path)
        else { return outcome }
        let newFolder = library.appending(path: "Application Support/\(bundleID)")
        let pending = newFolder.appending(path: pendingMarker)
        let attempts = (try? String(contentsOf: pending, encoding: .utf8)).flatMap { Int($0) }
        // Nera's own data is never replaced: only a first run, or one that was waiting for Lumen, migrates.
        guard !fm.fileExists(atPath: newFolder.path) || attempts != nil else { return outcome }
        if lumenIsRunning {
            markPending(newFolder, attempts: attempts ?? 0)
            outcome.deferred = true
            return outcome
        }

        // The cookie key: without it, the copied profiles' cookies and saved passwords can't be decrypted.
        let old = cookieKeyItem(product: "Lumen", bundleID: oldID)
        let new = cookieKeyItem(product: "Nera", bundleID: bundleID)
        var skip: Set<String> = []
        if keychain.exists(service: old.service, account: old.account) {
            if let secret = keychain.password(service: old.service, account: old.account) {
                // A key Nera made while waiting (its own short session) is kept under another name.
                if let own = keychain.password(service: new.service, account: new.account), own != secret {
                    _ = keychain.store(own, service: new.service + " before Lumen", account: new.account)
                }
                outcome.copiedKey = keychain.store(secret, service: new.service, account: new.account)
            }
            if !outcome.copiedKey {
                skip.insert("Chromium")
                outcome.skippedSignIns = true
            }
        }

        // The data folder (Nera's waiting-session files, if any, are replaced by Lumen's data and kept aside).
        do {
            if fm.fileExists(atPath: newFolder.path) {
                try fm.moveItem(at: newFolder, to: newFolder.deletingLastPathComponent().appending(path: "\(bundleID)-before-lumen"))
            }
            try copyContents(of: oldFolder, to: newFolder, skipping: skip)
            outcome.copiedData = true
        } catch {
            try? fm.removeItem(at: newFolder)
            markPending(newFolder, attempts: (attempts ?? 0) + 1)  // tried again at the next launch, three times at most
            return outcome
        }

        // WebKit's website data (cookies and storage of pages shown with WebKit).
        for folder in ["WebKit", "HTTPStorages"] {
            let from = library.appending(path: "\(folder)/\(oldID)")
            let to = library.appending(path: "\(folder)/\(bundleID)")
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: from, to: to) }
        }

        // Settings: the user's choices, under their Nera names.
        if let oldDefaults {
            for (key, value) in oldDefaults.dictionaryRepresentation() where key.hasPrefix("Lumen") && !settingsNotCopied.contains(key) {
                let renamed = "Nera" + key.dropFirst("Lumen".count)
                if newDefaults.object(forKey: renamed) == nil {
                    newDefaults.set(value, forKey: renamed)
                    outcome.copiedSettings += 1
                }
            }
        }
        fm.createFile(atPath: oldFolder.appending(path: doneMarker).path, contents: Data())
        return outcome
    }

    /// Lumen's data folder: Application Support, or the sandbox container very early builds used.
    public static func lumenFolder(_ oldID: String, library: URL) -> URL? {
        let candidates = [
            library.appending(path: "Application Support/\(oldID)"),
            library.appending(path: "Containers/\(oldID)/Data/Library/Application Support/\(oldID)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "library.json").path) }
    }

    /// Notes that the migration is still to happen; after three failed attempts it stops trying.
    static func markPending(_ folder: URL, attempts: Int) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appending(path: pendingMarker)
        if attempts >= 3 {
            try? fm.removeItem(at: marker)
        } else {
            try? Data(String(attempts).utf8).write(to: marker)
        }
    }

    /// Chromium's per-run files (which process holds the profile, and how to reach it): copied, they'd make Nera's
    /// Chromium believe another browser owns the profile.
    static let runtimeFiles: Set = ["SingletonLock", "SingletonSocket", "SingletonCookie", "RunningChromeVersion"]
    /// Caches Chromium rebuilds by itself: not worth copying.
    static let caches: Set = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "GraphiteDawnCache", "ShaderCache", "CacheStorage", "ScriptCache",
    ]

    /// Copies a folder's contents recursively (cloned on APFS, so it's quick), without runtime files, caches and the
    /// top-level names in `skipping`.
    static func copyContents(of source: URL, to destination: URL, skipping: Set<String> = []) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: source.path)
        where !runtimeFiles.contains(name) && !caches.contains(name) && !skipping.contains(name) && name != doneMarker {
            let from = source.appending(path: name)
            let to = destination.appending(path: name)
            var isDirectory: ObjCBool = false
            let isLink = (try? fm.destinationOfSymbolicLink(atPath: from.path)) != nil
            if !isLink, fm.fileExists(atPath: from.path, isDirectory: &isDirectory), isDirectory.boolValue {
                try copyContents(of: from, to: to)
            } else if !fm.fileExists(atPath: to.path) {
                try fm.copyItem(at: from, to: to)
            }
        }
    }
}

#if os(macOS)
    /// The login Keychain. Reading Lumen's item asks the user once to allow Nera to use it.
    public struct SystemMigrationKeychain: MigrationKeychain {
        /// The login Keychain.
        public init() {}

        private func query(_ service: String, _ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        }

        /// Whether the item exists (attributes only: no prompt).
        public func exists(service: String, account: String) -> Bool {
            var q = query(service, account)
            q[kSecReturnAttributes as String] = true
            return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
        }

        /// The item's secret.
        public func password(service: String, account: String) -> Data? {
            var q = query(service, account)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
        }

        /// Stores the item (only this app may read it without asking), replacing an existing secret.
        public func store(_ password: Data, service: String, account: String) -> Bool {
            let status = SecItemUpdate(query(service, account) as CFDictionary, [kSecValueData as String: password] as CFDictionary)
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            var item = query(service, account)
            item[kSecAttrLabel as String] = service
            item[kSecValueData as String] = password
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
    }
#endif
