// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import Foundation

/// Versioned, atomic JSON file. A corrupt file is moved aside (never silently overwritten), so
/// user data can always be recovered (SR-030).
public struct JSONFileStore: StatePersisting {
    /// The schema version this build writes. Bump only with a migration and a fixture test.
    public static let schemaVersion = 1

    /// Location of the library file.
    public let fileURL: URL
    /// The version this store writes (``schemaVersion`` in the app; injectable for migration tests).
    public let currentVersion: Int
    /// Steps that upgrade older files, one per version.
    public let migrations: [LibraryMigration]

    /// Creates a store for a specific file.
    public init(fileURL: URL, currentVersion: Int = JSONFileStore.schemaVersion, migrations: [LibraryMigration] = LibraryMigration.all) {
        self.fileURL = fileURL
        self.currentVersion = currentVersion
        self.migrations = migrations
    }

    /// `~/Library/Application Support/<bundle id>/library.json` (sandbox-aware on all platforms).
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.nera.browser") throws -> JSONFileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appending(path: bundleID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return JSONFileStore(fileURL: dir.appending(path: "library.json"))
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var state: BrowserState
    }

    /// Loads the library. Returns `nil` if there's no file, or if the file was unreadable (it's then
    /// moved to `library.corrupt-<timestamp>.json`). Throws ``PersistenceError/newerSchema(_:)`` rather
    /// than downgrading a file written by a newer app version.
    public func load() throws -> BrowserState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var data = try Data(contentsOf: fileURL)
        do {
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let version = json["schemaVersion"] as? Int
            else { throw CocoaError(.coderReadCorrupt) }
            guard version <= currentVersion else { throw PersistenceError.newerSchema(version) }
            if version < currentVersion {
                try backUp(version: version)
                json = try migrate(json, from: version)
                data = try JSONSerialization.data(withJSONObject: json)
            }
            return try decoder.decode(Envelope.self, from: data).state
        } catch let error as PersistenceError {
            throw error
        } catch {
            try quarantineCorruptFile()
            return nil
        }
    }

    /// Runs every step from `version` up to ``currentVersion``, in order.
    func migrate(_ json: [String: Any], from version: Int) throws -> [String: Any] {
        var json = json
        for step in version..<currentVersion {
            guard let migration = migrations.first(where: { $0.fromVersion == step }) else {
                throw PersistenceError.missingMigration(step)
            }
            guard var state = json["state"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
            try migration.migrate(&state)
            json["state"] = state
            json["schemaVersion"] = step + 1
        }
        return json
    }

    /// Keeps the pre-migration file as `library.v<n>.json`, so an upgrade can always be undone by hand.
    private func backUp(version: Int) throws {
        let dest = fileURL.deletingLastPathComponent().appending(path: "library.v\(version).json")
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.copyItem(at: fileURL, to: dest)
    }

    /// Writes the library atomically. On iOS the file is protected until first unlock.
    public func save(_ state: BrowserState) throws {
        let data = try encoder.encode(Envelope(schemaVersion: currentVersion, state: state))
        #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    private func quarantineCorruptFile() throws {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = fileURL.deletingLastPathComponent().appending(path: "library.corrupt-\(stamp).json")
        try FileManager.default.moveItem(at: fileURL, to: dest)
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Errors loading the library.
public enum PersistenceError: Error, Equatable {
    /// The file was written by a newer app version. Loading is refused rather than downgrading and losing data.
    case newerSchema(Int)
    /// No migration step exists from this version (a programming error caught by tests). The file is left untouched.
    case missingMigration(Int)
}

/// One upgrade step of the library format, from `fromVersion` to `fromVersion + 1`. Steps work on the decoded
/// JSON of the `state` object, so they never depend on today's Swift types (which change over time).
public struct LibraryMigration: Sendable {
    /// The version this step upgrades from.
    public let fromVersion: Int
    /// Rewrites the `state` object in place.
    public let migrate: @Sendable (inout [String: Any]) throws -> Void

    /// Creates a step.
    public init(from fromVersion: Int, _ migrate: @escaping @Sendable (inout [String: Any]) throws -> Void) {
        self.fromVersion = fromVersion
        self.migrate = migrate
    }

    /// Every step the app ships. Add one (with a fixture under Tests/StorageTests/Fixtures) whenever
    /// ``JSONFileStore/schemaVersion`` is bumped.
    public static let all: [LibraryMigration] = []
}
