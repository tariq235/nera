// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
public import Foundation
import Security

/// Chrome extension package (CRX3) parsing and signature verification (FEAT-029).
///
/// A CRX3 file is `"Cr24"`, version 3, a protobuf header with signatures ("proofs"), then a ZIP archive. Nera
/// installs a package only if:
/// - a proof by the **developer key** (whose hash is the extension ID) verifies, and
/// - for Chrome Web Store installs, a proof by the **Web Store publisher key** verifies too.
///
/// Each proof signs `"CRX3 SignedData\0" ‖ len(signed_header_data) as UInt32 LE ‖ signed_header_data ‖ archive`.
public enum CRX3 {
    /// SHA-256 of the Chrome Web Store publisher key (same value as Chromium's `kPublisherKeyHash`; checked
    /// against real store packages, which all carry this ECDSA proof).
    public static let webStorePublisherKeyHash = Data(
        [
            0x61, 0xf7, 0xf2, 0xa6, 0xbf, 0xcf, 0x74, 0xcd, 0x0b, 0xc1, 0xfe, 0x24, 0x97, 0xcc, 0x9b, 0x04,
            0x25, 0x4c, 0x65, 0x8f, 0x79, 0xf2, 0x14, 0x53, 0x92, 0x86, 0x7e, 0xa8, 0x36, 0x63, 0x67, 0xcf,
        ])

    /// A verified package.
    public struct Package: Sendable {
        /// The extension ID (32 letters a–p), derived from the developer key.
        public let id: String
        /// The developer key (DER SubjectPublicKeyInfo); written into the manifest's `key` so Chromium keeps the ID.
        public let developerKey: Data
        /// The ZIP archive with the extension's files.
        public let archive: Data
        /// Whether the Chrome Web Store signed it.
        public let isFromWebStore: Bool
    }

    /// Why a package was refused.
    public enum Failure: Error, Equatable, Sendable {
        /// Not a CRX3 file.
        case notCRX3
        /// The header is malformed.
        case malformedHeader
        /// No valid signature by the key the extension ID comes from.
        case badDeveloperSignature
        /// A Web Store package without a valid Web Store signature.
        case notSignedByWebStore
        /// The extension ID isn't the expected one.
        case unexpectedID(String)
    }

    /// Parses and verifies a package. `expectedID` (when installing a known store item) must match.
    public static func verify(
        _ data: Data, requireWebStore: Bool, expectedID: String? = nil, publisherKeyHash: Data = webStorePublisherKeyHash
    ) throws -> Package {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes[0..<4] == [0x43, 0x72, 0x32, 0x34], uint32(bytes, 4) == 3 else { throw Failure.notCRX3 }
        let headerSize = Int(uint32(bytes, 8))
        guard headerSize > 0, 12 + headerSize <= bytes.count else { throw Failure.malformedHeader }
        let header = Array(bytes[12..<(12 + headerSize)])
        let archive = Data(bytes[(12 + headerSize)...])

        let headerFields = try Protobuf.fields(header)
        guard let signedHeader = headerFields.last(where: { $0.number == 10000 })?.bytes,
            let crxID = try Protobuf.fields(signedHeader).first(where: { $0.number == 1 })?.bytes, crxID.count == 16
        else { throw Failure.malformedHeader }

        var message = Data("CRX3 SignedData\0".utf8)
        withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { message.append(contentsOf: $0) }
        message.append(contentsOf: signedHeader)
        message.append(archive)

        var developerKey: Data?
        var webStore = false
        for field in headerFields where field.number == 2 || field.number == 3 {
            guard let proof = field.bytes, let parts = try? Protobuf.fields(proof),
                let key = parts.first(where: { $0.number == 1 })?.bytes, let signature = parts.first(where: { $0.number == 2 })?.bytes
            else { continue }
            let keyHash = Data(SHA256.hash(data: key))
            let valid =
                field.number == 2
                ? verifyRSA(key: key, signature: signature, message: message)
                : verifyECDSA(key: key, signature: signature, message: message)
            guard valid else { continue }
            if keyHash.prefix(16) == Data(crxID) { developerKey = Data(key) }
            if keyHash == publisherKeyHash { webStore = true }
        }
        guard let developerKey else { throw Failure.badDeveloperSignature }
        if requireWebStore, !webStore { throw Failure.notSignedByWebStore }
        let id = extensionID(crxID: Data(crxID))
        if let expectedID, expectedID != id { throw Failure.unexpectedID(id) }
        return Package(id: id, developerKey: developerKey, archive: archive, isFromWebStore: webStore)
    }

    /// Chromium's extension ID: the first 16 bytes of SHA-256(key), each hex digit mapped 0–f → a–p.
    public static func extensionID(crxID: Data) -> String {
        String(crxID.prefix(16).flatMap { [$0 >> 4, $0 & 0xf] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    /// The extension ID a developer key gives.
    public static func extensionID(forKey key: Data) -> String { extensionID(crxID: Data(SHA256.hash(data: key))) }

    // MARK: Signatures

    static func verifyRSA(key spki: [UInt8], signature: [UInt8], message: Data) -> Bool {
        guard let pkcs1 = DER.subjectPublicKey(spki) else { return false }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, Data(signature) as CFData, nil)
    }

    static func verifyECDSA(key spki: [UInt8], signature: [UInt8], message: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: spki),
            let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature)
        else { return false }
        return key.isValidSignature(sig, for: message)
    }

    static func uint32(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }
}

/// The few protobuf wire-format pieces CRX3 needs (length-delimited and varint fields). Untrusted input: every
/// length is bounds-checked.
enum Protobuf {
    struct Field {
        let number: Int
        let bytes: [UInt8]?
        let value: UInt64?
    }

    static func fields(_ b: [UInt8]) throws -> [Field] {
        var i = 0
        var out: [Field] = []
        while i < b.count {
            let key = try varint(b, &i)
            let number = Int(key >> 3)
            switch key & 7 {
            case 0: out.append(Field(number: number, bytes: nil, value: try varint(b, &i)))
            case 2:
                let length = try varint(b, &i)
                guard length <= UInt64(b.count - i) else { throw CRX3.Failure.malformedHeader }
                out.append(Field(number: number, bytes: Array(b[i..<(i + Int(length))]), value: nil))
                i += Int(length)
            default: throw CRX3.Failure.malformedHeader
            }
        }
        return out
    }

    static func varint(_ b: [UInt8], _ i: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < b.count, shift < 64 {
            let byte = b[i]
            i += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw CRX3.Failure.malformedHeader
    }
}

/// Minimal DER reading: the key bits of a SubjectPublicKeyInfo.
enum DER {
    /// `SEQUENCE { SEQUENCE algorithm, BIT STRING subjectPublicKey }` → the BIT STRING's contents (PKCS#1 for RSA).
    static func subjectPublicKey(_ spki: [UInt8]) -> [UInt8]? {
        var i = 0
        guard let outer = element(spki, &i, tag: 0x30) else { return nil }
        var j = 0
        guard element(outer, &j, tag: 0x30) != nil, let bits = element(outer, &j, tag: 0x03), bits.first == 0 else { return nil }
        return Array(bits.dropFirst())
    }

    static func element(_ b: [UInt8], _ i: inout Int, tag: UInt8) -> [UInt8]? {
        guard i + 2 <= b.count, b[i] == tag else { return nil }
        var length = Int(b[i + 1])
        var start = i + 2
        if length & 0x80 != 0 {
            let lengthBytes = length & 0x7f
            guard (1...4).contains(lengthBytes), start + lengthBytes <= b.count else { return nil }
            length = b[start..<(start + lengthBytes)].reduce(0) { $0 << 8 | Int($1) }
            start += lengthBytes
        }
        guard length >= 0, start + length <= b.count else { return nil }
        i = start + length
        return Array(b[start..<(start + length)])
    }
}
