// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import BrowserData

/// Lumen → Nera: on Nera's first run, Lumen's data, cookie key, WebKit data and settings are copied once, never over
/// Nera's own data, never while Lumen runs, never sign-ins that couldn't be decrypted.
@Suite("Rename migration")
struct RenameMigrationTests {
    final class FakeKeychain: MigrationKeychain {
        var items: [String: Data] = [:]
        var unreadable: Set<String> = []
        func exists(service: String, account: String) -> Bool { items["\(service)|\(account)"] != nil }
        func password(service: String, account: String) -> Data? {
            unreadable.contains(service) ? nil : items["\(service)|\(account)"]
        }
        func store(_ password: Data, service: String, account: String) -> Bool {
            items["\(service)|\(account)"] = password
            return true
        }
    }

    struct Fixture {
        let library: URL
        let keychain = FakeKeychain()
        let old: UserDefaults
        let new: UserDefaults
        var lumen: URL { library.appending(path: "Application Support/dev.lumen.browser") }
        var nera: URL { library.appending(path: "Application Support/dev.nera.browser") }
        let lumenKey = "Lumen Safe Storage (dev.lumen.browser)"
        let neraKey = "Nera Safe Storage (dev.nera.browser)"

        @discardableResult func run(lumenIsRunning: Bool = false) -> RenameMigration.Outcome {
            RenameMigration.run(
                bundleID: "dev.nera.browser", library: library, keychain: keychain, oldDefaults: old, newDefaults: new,
                lumenIsRunning: lumenIsRunning)
        }
    }

    func setUp() throws -> Fixture {
        let library = FileManager.default.temporaryDirectory.appending(path: "rename-\(UUID().uuidString)")
        let f = Fixture(
            library: library, old: try #require(UserDefaults(suiteName: "test.old.\(UUID().uuidString)")),
            new: try #require(UserDefaults(suiteName: "test.new.\(UUID().uuidString)")))
        let fm = FileManager.default
        try fm.createDirectory(at: f.lumen.appending(path: "Chromium/Default/Cache"), withIntermediateDirectories: true)
        try Data("{\"spaces\":[]}".utf8).write(to: f.lumen.appending(path: "library.json"))
        try Data("cookies".utf8).write(to: f.lumen.appending(path: "Chromium/Default/Cookies"))
        try Data("cache".utf8).write(to: f.lumen.appending(path: "Chromium/Default/Cache/data_0"))
        try fm.createSymbolicLink(atPath: f.lumen.appending(path: "Chromium/SingletonLock").path, withDestinationPath: "host-123")
        try fm.createDirectory(at: library.appending(path: "WebKit/dev.lumen.browser"), withIntermediateDirectories: true)
        try Data("webkit".utf8).write(to: library.appending(path: "WebKit/dev.lumen.browser/cookies"))
        f.keychain.items["\(f.lumenKey)|Lumen"] = Data("secret".utf8)
        f.old.set(false, forKey: "LumenCheckForUpdates")
        f.old.set(true, forKey: "LumenOfferedDefaultBrowser")
        f.old.set("x", forKey: "SomethingElse")
        return f
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func theFirstRunCopiesEverythingOnce() throws {
        let f = try setUp()
        #expect(RenameMigration.isDue(bundleID: "dev.nera.browser", library: f.library))
        let outcome = f.run()
        #expect(outcome.copiedData && outcome.copiedKey && outcome.copiedSettings == 1 && !outcome.skippedSignIns)
        #expect(try Data(contentsOf: f.nera.appending(path: "Chromium/Default/Cookies")) == Data("cookies".utf8))
        #expect(f.keychain.items["\(f.neraKey)|Nera"] == Data("secret".utf8), "sign-ins stay readable")
        #expect(exists(f.library.appending(path: "WebKit/dev.nera.browser/cookies")), "WebKit's site data too")
        #expect(f.new.object(forKey: "NeraCheckForUpdates") as? Bool == false)
        #expect(f.new.object(forKey: "NeraOfferedDefaultBrowser") == nil, "Nera still offers to be the default browser")
        #expect(!exists(f.nera.appending(path: "Chromium/SingletonLock")), "Lumen's Chromium lock isn't copied")
        #expect(!exists(f.nera.appending(path: "Chromium/Default/Cache")), "caches aren't copied")
        #expect(exists(f.lumen.appending(path: "library.json")), "Lumen's data stays")
        #expect(!RenameMigration.isDue(bundleID: "dev.nera.browser", library: f.library))
    }

    @Test func reinstallingNeraDoesntBringLumensDataBack() throws {
        let f = try setUp()
        f.run()
        try FileManager.default.removeItem(at: f.nera)  // the uninstaller
        #expect(f.run() == RenameMigration.Outcome())
        #expect(!exists(f.nera))
    }

    @Test func neraOwnDataIsNeverReplaced() throws {
        let f = try setUp()
        try FileManager.default.createDirectory(at: f.nera, withIntermediateDirectories: true)
        try Data("{\"nera\":true}".utf8).write(to: f.nera.appending(path: "library.json"))
        #expect(f.run() == RenameMigration.Outcome())
        #expect(try Data(contentsOf: f.nera.appending(path: "library.json")) == Data("{\"nera\":true}".utf8))
        #expect(f.keychain.items["\(f.neraKey)|Nera"] == nil)
    }

    @Test func itWaitsWhileLumenRunsThenKeepsTheWaitingSessionsKeyAside() throws {
        let f = try setUp()
        let waiting = f.run(lumenIsRunning: true)
        #expect(waiting.deferred && !waiting.copiedData)
        // Nera ran meanwhile: its Chromium made its own key and some data.
        f.keychain.items["\(f.neraKey)|Nera"] = Data("nera's own".utf8)
        try Data("{\"waiting\":true}".utf8).write(to: f.nera.appending(path: "library.json"))
        let outcome = f.run()
        #expect(outcome.copiedData && outcome.copiedKey)
        #expect(f.keychain.items["\(f.neraKey)|Nera"] == Data("secret".utf8))
        #expect(f.keychain.items["\(f.neraKey) before Lumen|Nera"] == Data("nera's own".utf8), "kept, not lost")
        let aside = f.library.appending(path: "Application Support/dev.nera.browser-before-lumen/library.json")
        #expect(try Data(contentsOf: aside) == Data("{\"waiting\":true}".utf8))
    }

    @Test func signInsThatCantBeDecryptedArentCopied() throws {
        let f = try setUp()
        f.keychain.unreadable = [f.lumenKey]  // the user declined the Keychain prompt
        let outcome = f.run()
        #expect(outcome.copiedData && !outcome.copiedKey && outcome.skippedSignIns)
        #expect(exists(f.nera.appending(path: "library.json")) && !exists(f.nera.appending(path: "Chromium")))
    }

    @Test func aFailedCopyIsRetriedThreeTimesAtMost() throws {
        let f = try setUp()
        let locked = f.lumen.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        for _ in 0..<3 {
            #expect(!f.run().copiedData)
            #expect(
                RenameMigration.isDue(bundleID: "dev.nera.browser", library: f.library)
                    || !exists(f.nera.appending(path: ".awaiting-lumen")))
        }
        #expect(!RenameMigration.isDue(bundleID: "dev.nera.browser", library: f.library), "gives up after three attempts")
    }

    @Test func dataFromTheOldSandboxContainerIsFound() throws {
        let f = try setUp()
        let container = f.library.appending(path: "Containers/dev.lumen.browser/Data/Library/Application Support/dev.lumen.browser")
        try FileManager.default.createDirectory(at: container.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: f.lumen, to: container)
        #expect(f.run().copiedData)
        #expect(exists(f.nera.appending(path: "library.json")))
    }

    @Test func otherAppsAndMacsWithoutLumenAreLeftAlone() throws {
        #expect(RenameMigration.previousBundleID(of: "dev.nera.browser.debug") == "dev.lumen.browser.debug")
        #expect(RenameMigration.previousBundleID(of: "com.example.fork") == nil)
        let empty = FileManager.default.temporaryDirectory.appending(path: "rename-empty-\(UUID().uuidString)")
        let keychain = FakeKeychain()
        let defaults = try #require(UserDefaults(suiteName: "test.none.\(UUID().uuidString)"))
        #expect(
            RenameMigration.run(bundleID: "dev.nera.browser", library: empty, keychain: keychain, oldDefaults: nil, newDefaults: defaults)
                == .init())
        #expect(!RenameMigration.isDue(bundleID: "dev.nera.browser", library: empty))
    }
}

/// On a copy of a real Lumen install (opt-in): `NERA_MIGRATION_SOURCE=<copy of Lumen's data folder> swift test --filter RealData`.
@Suite("Rename migration on real data", .enabled(if: ProcessInfo.processInfo.environment["NERA_MIGRATION_SOURCE"] != nil))
struct RenameMigrationRealDataTests {
    @Test func aRealLumenFolderArrivesWhole() throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["NERA_MIGRATION_SOURCE"]))
        let library = FileManager.default.temporaryDirectory.appending(path: "rename-real-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library.appending(path: "Application Support"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: library.appending(path: "Application Support/dev.lumen.browser"))
        let keychain = RenameMigrationTests.FakeKeychain()
        let defaults = try #require(UserDefaults(suiteName: "test.real.\(UUID().uuidString)"))
        let outcome = RenameMigration.run(
            bundleID: "dev.nera.browser", library: library, keychain: keychain, oldDefaults: nil, newDefaults: defaults)
        #expect(outcome.copiedData)
        func files(_ root: URL) -> [String: Int] {
            var out: [String: Int] = [:]
            let base = root.resolvingSymlinksInPath().path
            let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            while let url = walker?.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
                let parts = Set(path.split(separator: "/").map(String.init))
                guard parts.isDisjoint(with: RenameMigration.caches), !path.hasSuffix(RenameMigration.doneMarker) else { continue }
                out[path] = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            }
            return out
        }
        let before = files(library.appending(path: "Application Support/dev.lumen.browser"))
        let after = files(library.appending(path: "Application Support/dev.nera.browser"))
        let missing = before.filter { after[$0.key] != $0.value }.map(\.key).sorted()
        let extra = after.keys.filter { before[$0] == nil }.sorted()
        #expect(
            before.count > 10 && missing.isEmpty && extra.isEmpty, "missing or different: \(missing.prefix(8)); extra: \(extra.prefix(8))")
    }
}
