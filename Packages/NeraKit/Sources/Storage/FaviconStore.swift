// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Site icons cached by host, so tabs show their icon before their page is loaded.
/// Only icons from persistent profiles are stored; private pages never write here.
public final class FaviconStore: @unchecked Sendable {
    // @unchecked: `memory` is guarded by `lock`.
    private let directory: URL?
    private var memory: [String: Data] = [:]
    private var missing: Set<String> = []
    private let lock = NSLock()
    /// Icons larger than this are ignored (engines deliver ≤ 64 px PNGs).
    public static let maxBytes = 256 * 1024

    /// A store in `directory`, or memory only when nil.
    public init(directory: URL?) {
        self.directory = directory
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// `Application Support/<bundle id>/Favicons`.
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.nera.browser") -> FaviconStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FaviconStore(directory: base.appending(path: "\(bundleID)/Favicons", directoryHint: .isDirectory))
    }

    /// The cached icon for a host.
    public func icon(forHost host: String) -> Data? {
        let key = Self.key(host)
        guard !key.isEmpty else { return nil }
        return lock.withLock {
            if let data = memory[key] { return data }
            if missing.contains(key) { return nil }
            guard let file = directory?.appending(path: key + ".png"), let data = try? Data(contentsOf: file) else {
                missing.insert(key)
                return nil
            }
            memory[key] = data
            return data
        }
    }

    /// Stores a host's icon.
    public func save(_ png: Data, forHost host: String) {
        let key = Self.key(host)
        guard !key.isEmpty, !png.isEmpty, png.count <= Self.maxBytes else { return }
        lock.withLock {
            guard memory[key] != png else { return }
            memory[key] = png
            missing.remove(key)
            if let file = directory?.appending(path: key + ".png") { try? png.write(to: file, options: .atomic) }
        }
    }

    /// Removes every cached icon.
    public func removeAll() {
        lock.withLock {
            memory.removeAll()
            missing.removeAll()
            if let directory {
                for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    /// A safe file name for a host: lowercase letters, digits, dots and dashes only (no path traversal).
    static func key(_ host: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        let cleaned = String(host.lowercased().filter { allowed.contains($0) }.prefix(253))
        return cleaned.allSatisfy { $0 == "." } ? "" : cleaned
    }
}
