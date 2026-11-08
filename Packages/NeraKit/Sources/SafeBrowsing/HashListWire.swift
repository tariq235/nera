// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The few Safe Browsing v5 protobuf messages Nera reads, decoded by hand (the API serves only protobuf; no
/// third-party code). Field numbers are those of `google.security.safebrowsing.v5`, checked against live responses
/// (a decoded `se-4b` list matches Google's SHA-256 checksum).
struct ProtoReader {
    enum Field {
        case varint(UInt64)
        case bytes(Data)
        case fixed64
        case fixed32
    }

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    /// The next field, or nil at the end. Throws on malformed input (untrusted network data).
    mutating func next() throws -> (number: Int, value: Field)? {
        guard offset < data.endIndex else { return nil }
        let key = try varint()
        let number = Int(key >> 3)
        switch key & 7 {
        case 0: return (number, .varint(try varint()))
        case 1:
            try skip(8)
            return (number, .fixed64)
        case 2:
            guard let length = Int(exactly: try varint()), length <= data.endIndex - offset else {
                throw SafeBrowsingError.malformedResponse
            }
            let value = data[offset..<(offset + length)]
            offset += length
            return (number, .bytes(Data(value)))
        case 5:
            try skip(4)
            return (number, .fixed32)
        default: throw SafeBrowsingError.malformedResponse
        }
    }

    private mutating func skip(_ n: Int) throws {
        guard n <= data.endIndex - offset else { throw SafeBrowsingError.malformedResponse }
        offset += n
    }

    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.endIndex, shift < 64 {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
        }
        throw SafeBrowsingError.malformedResponse
    }
}

/// A `google.protobuf.Duration` in seconds.
func durationSeconds(_ data: Data) throws -> TimeInterval {
    var reader = ProtoReader(data)
    var seconds: TimeInterval = 0
    while let (number, value) = try reader.next() {
        if case .varint(let v) = value {
            if number == 1 { seconds += TimeInterval(Int64(bitPattern: v)) }
            if number == 2 { seconds += TimeInterval(Int32(truncatingIfNeeded: v)) / 1e9 }
        }
    }
    return seconds
}

/// `HashList` (hashList.get): one update of a list of 4-byte hash prefixes.
struct HashListUpdate {
    var name = ""
    var version = Data()
    var partial = false
    /// Indices into the current sorted list to remove first.
    var removals: [UInt32] = []
    /// New prefixes, sorted, as big-endian integers.
    var additions: [UInt32] = []
    var minimumWait: TimeInterval = 0
    var checksum = Data()

    init(_ data: Data) throws {
        var reader = ProtoReader(data)
        while let (number, value) = try reader.next() {
            switch (number, value) {
            case (1, .bytes(let d)): name = String(decoding: d, as: UTF8.self)
            case (2, .bytes(let d)): version = d
            case (3, .varint(let v)): partial = v != 0
            case (4, .bytes(let d)): additions = try RiceDecoder.decode32(d)
            case (5, .bytes(let d)): removals = try RiceDecoder.decode32(d)
            case (6, .bytes(let d)): minimumWait = try durationSeconds(d)
            case (7, .bytes(let d)): checksum = d
            case (9, _), (10, _), (11, _): throw SafeBrowsingError.unsupportedHashLength  // only 4-byte lists are used
            default: break
            }
        }
    }
}

/// `SearchHashesResponse` (hashes.search): full hashes matching the prefixes sent, and how long to cache the answer.
struct HashSearchResponse {
    struct Match {
        var fullHash: Data
        /// Threats the hash is listed for (canary and unknown attributes already dropped; see ``frameOnly``).
        var threats: Set<SafeBrowsingThreat>
        /// Threats listed for frames only (FRAME_ONLY): not enforced on top-level pages.
        var frameOnly: Set<SafeBrowsingThreat>
    }

    var matches: [Match] = []
    var cacheDuration: TimeInterval = 300

    init(_ data: Data) throws {
        var reader = ProtoReader(data)
        while let (number, value) = try reader.next() {
            switch (number, value) {
            case (1, .bytes(let d)): matches.append(try Self.match(d))
            case (2, .bytes(let d)): cacheDuration = try durationSeconds(d)
            default: break
            }
        }
    }

    private static func match(_ data: Data) throws -> Match {
        var reader = ProtoReader(data)
        var result = Match(fullHash: Data(), threats: [], frameOnly: [])
        while let (number, value) = try reader.next() {
            switch (number, value) {
            case (1, .bytes(let d)): result.fullHash = d
            case (2, .bytes(let d)):
                var detail = ProtoReader(d)
                var threat: SafeBrowsingThreat?
                var attributes: [UInt64] = []
                while let (n, v) = try detail.next() {
                    if n == 1, case .varint(let t) = v { threat = Int(exactly: t).flatMap(SafeBrowsingThreat.init(rawValue:)) }
                    if n == 2, case .varint(let a) = v { attributes.append(a) }
                    if n == 2, case .bytes(let packed) = v {  // packed repeated enum (values below 128: one byte each)
                        attributes += packed.map { UInt64($0) }
                    }
                }
                // CANARY (1): not for enforcement; unknown attributes: discard the detail; FRAME_ONLY (2): frames only.
                guard let threat, attributes.allSatisfy({ $0 == 1 || $0 == 2 }), !attributes.contains(1) else { continue }
                if attributes.contains(2) { result.frameOnly.insert(threat) } else { result.threats.insert(threat) }
            default: break
            }
        }
        return result
    }
}

/// Golomb-Rice decoding of `RiceDeltaEncoded32Bit` (v5 "Local Database"): the first value is stored as is; each
/// further value adds a delta whose quotient is unary (ones ended by a zero) and whose remainder is `riceParameter`
/// bits, read least-significant bit first from a little-endian bit stream.
enum RiceDecoder {
    static func decode32(_ message: Data) throws -> [UInt32] {
        var reader = ProtoReader(message)
        var first: UInt64 = 0
        var k = 0
        var entries = 0
        var encoded = Data()
        while let (number, value) = try reader.next() {
            switch (number, value) {
            case (1, .varint(let v)): first = v
            case (2, .varint(let v)): k = Int(exactly: v) ?? -1
            case (3, .varint(let v)): entries = Int(exactly: v) ?? -1
            case (4, .bytes(let d)): encoded = d
            default: break
            }
        }
        guard first <= UInt64(UInt32.max), (0...31).contains(k), (0...(encoded.count * 8)).contains(entries) else {
            throw SafeBrowsingError.malformedResponse
        }
        var values = [UInt32]()
        values.reserveCapacity(entries + 1)
        values.append(UInt32(first))
        let bytes = [UInt8](encoded)
        var bit = 0
        let totalBits = bytes.count * 8
        func readBit() throws -> UInt32 {
            guard bit < totalBits else { throw SafeBrowsingError.malformedResponse }
            let b = UInt32(bytes[bit >> 3] >> UInt8(bit & 7)) & 1
            bit += 1
            return b
        }
        var current = UInt32(first)
        for _ in 0..<entries {
            var quotient: UInt32 = 0
            while try readBit() == 1 { quotient &+= 1 }
            var remainder: UInt32 = 0
            for i in 0..<k { remainder |= try readBit() << UInt32(i) }
            current &+= (quotient << UInt32(k)) &+ remainder
            values.append(current)
        }
        return values
    }
}
