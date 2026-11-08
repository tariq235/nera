// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation

/// One local threat list: sorted 4-byte hash prefixes (as big-endian integers), kept in a file and memory-mapped,
/// so millions of prefixes cost almost no resident memory and a lookup touches a few pages.
struct PrefixList {
    private let data: Data

    /// An empty list.
    init() { data = Data() }

    /// The list stored at `file`, mapped (nil if missing or damaged).
    init?(file: URL) {
        guard let mapped = try? Data(contentsOf: file, options: .alwaysMapped), mapped.count % 4 == 0 else { return nil }
        data = mapped
    }

    var count: Int { data.count / 4 }

    func value(at index: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self) }
    }

    /// Binary search.
    func contains(_ prefix: UInt32) -> Bool {
        var low = 0
        var high = count - 1
        while low <= high {
            let mid = (low + high) / 2
            let v = value(at: mid)
            if v == prefix { return true }
            if v < prefix { low = mid + 1 } else { high = mid - 1 }
        }
        return false
    }

    var values: [UInt32] {
        data.withUnsafeBytes { raw in Array(raw.bindMemory(to: UInt32.self)) }
    }

    /// Writes sorted `values` to `file` atomically and maps it.
    static func write(_ values: [UInt32], to file: URL) throws -> PrefixList {
        let bytes = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try bytes.write(to: file, options: .atomic)
        return PrefixList(file: file) ?? PrefixList()
    }

    /// The list after `update`: removals (indices into the current list) first, then the sorted additions merged in.
    static func applying(_ update: HashListUpdate, to current: [UInt32]) throws -> [UInt32] {
        var base = update.partial ? current : []
        if update.partial, !update.removals.isEmpty {
            let remove = Set(update.removals.map(Int.init))
            guard remove.allSatisfy({ $0 < base.count }) else { throw SafeBrowsingError.inconsistentUpdate }
            base = base.enumerated().compactMap { remove.contains($0.offset) ? nil : $0.element }
        }
        let additions = update.additions.isEmpty ? [] : update.additions.sorted()
        var merged: [UInt32] = []
        merged.reserveCapacity(base.count + additions.count)
        var i = 0
        var j = 0
        while i < base.count || j < additions.count {
            if j == additions.count || (i < base.count && base[i] < additions[j]) {
                merged.append(base[i])
                i += 1
            } else {
                merged.append(additions[j])
                j += 1
            }
        }
        return merged
    }

    /// The checksum the server sends: SHA-256 of the sorted prefixes as big-endian bytes.
    static func checksum(_ values: [UInt32]) -> Data {
        let bigEndian = values.map(\.bigEndian)
        return bigEndian.withUnsafeBytes { Data(SHA256.hash(data: $0)) }
    }
}
