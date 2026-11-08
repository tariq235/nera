// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import Security
import Testing

@testable import Extensions

/// Builds real CRX3 packages with freshly generated keys.
struct CRXFactory {
    let developer: SecKey
    let developerSPKI: Data
    let publisher = P256.Signing.PrivateKey()

    init() throws {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil), let pub = SecKeyCopyPublicKey(key),
            let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil) as Data?
        else { throw CocoaError(.featureUnsupported) }
        developer = key
        developerSPKI = Self.spki(rsa: pkcs1)
    }

    var publisherHash: Data { Data(SHA256.hash(data: publisher.publicKey.derRepresentation)) }
    var id: String { CRX3.extensionID(forKey: developerSPKI) }

    /// A ZIP of the given files.
    static func zip(_ files: [String: String]) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appending(path: "crx-src-\(UUID().uuidString)")
        for (name, content) in files {
            let url = dir.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let out = dir.appendingPathExtension("zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", dir.path, out.path]
        try p.run()
        p.waitUntilExit()
        return try Data(contentsOf: out)
    }

    func crx(_ archive: Data, signByPublisher: Bool = true, tamper: Bool = false, idKey: Data? = nil) throws -> Data {
        let crxID = Data(SHA256.hash(data: idKey ?? developerSPKI)).prefix(16)
        let signedHeader = Self.field(1, crxID)
        var message = Data("CRX3 SignedData\0".utf8)
        withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { message.append(contentsOf: $0) }
        message.append(signedHeader)
        message.append(archive)
        var error: Unmanaged<CFError>?
        guard let rsaSig = SecKeyCreateSignature(developer, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) as Data? else {
            throw CocoaError(.featureUnsupported)
        }
        var header = Self.field(2, Self.field(1, developerSPKI) + Self.field(2, rsaSig))
        if signByPublisher {
            let sig = try publisher.signature(for: message).derRepresentation
            header += Self.field(3, Self.field(1, publisher.publicKey.derRepresentation) + Self.field(2, sig))
        }
        header += Self.field(10000, signedHeader)
        var out = Data("Cr24".utf8)
        for v in [UInt32(3), UInt32(header.count)] { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        out += header
        var body = archive
        if tamper { body[body.count / 2] ^= 0xff }
        return out + body
    }

    static func field(_ number: Int, _ bytes: Data) -> Data { varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }

    static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// Wraps a PKCS#1 RSA key in a SubjectPublicKeyInfo.
    static func spki(rsa pkcs1: Data) -> Data {
        let algorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let bitString = der(0x03, Data([0]) + pkcs1)
        return der(0x30, algorithm + bitString)
    }

    static func der(_ tag: UInt8, _ content: Data) -> Data {
        let n = content.count
        let length: Data =
            n < 0x80 ? Data([UInt8(n)]) : n < 0x100 ? Data([0x81, UInt8(n)]) : Data([0x82, UInt8(n >> 8), UInt8(n & 0xff)])
        return Data([tag]) + length + content
    }
}

@Suite("CRX3 verification")
struct CRX3Tests {
    let manifest = #"{"manifest_version":3,"name":"Test","version":"1.2.3"}"#

    @Test func validStorePackagesVerifyAndKeepTheirID() throws {
        let f = try CRXFactory()
        let data = try f.crx(CRXFactory.zip(["manifest.json": manifest]))
        let package = try CRX3.verify(data, requireWebStore: true, expectedID: f.id, publisherKeyHash: f.publisherHash)
        #expect(package.id == f.id && package.id.count == 32 && package.isFromWebStore)
        #expect(package.developerKey == f.developerSPKI)
    }

    @Test func tamperedUnsignedOrMislabelledPackagesAreRefused() throws {
        let f = try CRXFactory()
        let zip = try CRXFactory.zip(["manifest.json": manifest])
        #expect(throws: CRX3.Failure.badDeveloperSignature) {
            try CRX3.verify(f.crx(zip, tamper: true), requireWebStore: false, publisherKeyHash: f.publisherHash)
        }
        #expect(throws: CRX3.Failure.notSignedByWebStore) {
            try CRX3.verify(f.crx(zip, signByPublisher: false), requireWebStore: true, publisherKeyHash: f.publisherHash)
        }
        #expect(throws: CRX3.Failure.badDeveloperSignature, "an ID that isn't the signing key's") {
            try CRX3.verify(f.crx(zip, idKey: Data("someone else".utf8)), requireWebStore: false, publisherKeyHash: f.publisherHash)
        }
        #expect(throws: CRX3.Failure.unexpectedID(f.id)) {
            try CRX3.verify(
                f.crx(zip), requireWebStore: false, expectedID: String(repeating: "a", count: 32), publisherKeyHash: f.publisherHash)
        }
        #expect(throws: CRX3.Failure.notCRX3) { try CRX3.verify(zip, requireWebStore: false) }
    }

    @Test func malformedHeadersNeverCrash() throws {
        let f = try CRXFactory()
        let good = try [UInt8](f.crx(CRXFactory.zip(["manifest.json": manifest])))
        var seed: UInt64 = 1
        for _ in 0..<500 {
            var bytes = good
            for _ in 0..<6 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let i = 12 + Int(seed >> 33) % 600
                bytes[i] = UInt8(truncatingIfNeeded: seed >> 13)
            }
            _ = try? CRX3.verify(Data(bytes), requireWebStore: false, publisherKeyHash: f.publisherHash)
        }
    }

    @Test func webStorePublisherKeyMatchesChromium() {
        #expect(
            CRX3.webStorePublisherKeyHash.map { String(format: "%02x", $0) }.joined()
                == "61f7f2a6bfcf74cd0bc1fe2497cc9b04254c658f79f2145392867ea8366367cf")
    }
}

@Suite("Extension store")
struct ExtensionStoreTests {
    func store() -> ExtensionStore {
        ExtensionStore(directory: FileManager.default.temporaryDirectory.appending(path: "nera-ext-\(UUID().uuidString)"))
    }

    @Test func installReadsTheManifestKeepsTheIDAndSurvivesReopening() throws {
        let f = try CRXFactory()
        let zip = try CRXFactory.zip([
            "manifest.json":
                #"{"manifest_version":3,"name":"__MSG_appName__","default_locale":"en","version":"2.0","description":"Blocks ads","permissions":["storage","tabs"],"host_permissions":["<all_urls>"],"action":{"default_popup":"popup.html"},"icons":{"16":"i16.png","48":"i48.png","256":"i256.png"}}"#,
            "_locales/en/messages.json": #"{"appName":{"message":"Ad Blocker"}}"#,
        ])
        let s = store()
        let ext = try s.install(crx: f.crx(zip), from: .file)
        #expect(ext.id == f.id && ext.name == "Ad Blocker" && ext.version == "2.0" && ext.summary == "Blocks ads")
        #expect(ext.popupPath == "popup.html" && ext.iconPath == "i48.png", "largest icon ≤ 128 px")
        #expect(ext.readsAllSites && !ext.compatibilityNotes.isEmpty, "tabs + popup gets a note")
        let manifest =
            try JSONSerialization.jsonObject(with: Data(contentsOf: s.folder(for: ext).appending(path: "manifest.json"))) as? [String: Any]
        #expect(manifest?["key"] as? String == f.developerSPKI.base64EncodedString(), "Chromium keeps the store ID")
        #expect(ExtensionStore(directory: s.directory).extensions.map(\.id) == [f.id])
        #expect(s.enabledPaths == [s.folder(for: ext).path])
    }

    @Test func disableRemoveAndManifestV2() throws {
        let f = try CRXFactory()
        let s = store()
        let ext = try s.install(
            crx: f.crx(CRXFactory.zip(["manifest.json": #"{"manifest_version":3,"name":"A","version":"1"}"#])), from: .file)
        s.setEnabled(ext.id, false)
        #expect(s.enabledPaths.isEmpty && s.extensions.first?.isEnabled == false)
        s.remove(ext.id)
        #expect(s.extensions.isEmpty && !FileManager.default.fileExists(atPath: s.directory.appending(path: ext.id).path))
        let mv2 = try f.crx(CRXFactory.zip(["manifest.json": #"{"manifest_version":2,"name":"Old","version":"1"}"#]))
        #expect(throws: ExtensionInstallError.unsupportedManifestVersion(2)) { try s.install(crx: mv2, from: .file) }
        #expect(throws: ExtensionInstallError.invalidPackage(.notSignedByWebStore)) { try s.install(crx: mv2, from: .webStore) }
    }

    @Test func webStoreLinksAndIDs() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        #expect(ExtensionStore.webStoreID(from: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)") == id)
        #expect(ExtensionStore.webStoreID(from: "https://chrome.google.com/webstore/detail/x/\(id)?hl=en") == id)
        #expect(ExtensionStore.webStoreID(from: "  \(id.uppercased()) ") == id)
        #expect(ExtensionStore.webStoreID(from: "https://evil.example/detail/\(id)") == nil, "only Google's store")
        #expect(ExtensionStore.webStoreID(from: "not an id") == nil)
        #expect(ExtensionStore.webStoreDownloadURL(id: id, chromiumMajor: 156)?.host() == "clients2.google.com")
    }
}

/// Manual probe with real store packages: `NERA_CRX=/path/a.crx,/path/b.crx swift test --filter RealCRXProbe`.
@Suite("Real CRX probe")
struct RealCRXProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NERA_CRX"] != nil))
    func realStorePackagesVerify() throws {
        for path in (ProcessInfo.processInfo.environment["NERA_CRX"] ?? "").split(separator: ",") {
            let package = try CRX3.verify(Data(contentsOf: URL(fileURLWithPath: String(path))), requireWebStore: true)
            print("probe: \(path.split(separator: "/").last ?? ""): \(package.id) web store: \(package.isFromWebStore)")
        }
    }
}

/// Manual probe against the real Chrome Web Store: `NERA_NET_PROBE=1 swift test --filter WebStoreInstallProbe`.
@Suite("Web Store install probe")
struct WebStoreInstallProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NERA_NET_PROBE"] == "1"))
    func installsUBlockOriginLiteFromTheStore() async throws {
        let store = ExtensionStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "nera-ext-probe-\(UUID().uuidString)"))
        let ext = try await store.installFromWebStore(
            "https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh", chromiumMajor: 156)
        print(
            "probe: installed \(ext.name) \(ext.version) id \(ext.id) popup \(ext.popupPath ?? "-") notes \(ext.compatibilityNotes.count)")
        #expect(ext.id == "ddkjiahejlhfcafbddmgiahcphecmpfh" && ext.source == .webStore)
    }
}

@Suite("Native messaging hosts")
struct NativeMessagingHostsTests {
    func dir() -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "nera-nmh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func manifest(_ name: String, path: String = "/bin/ls", origins: [String] = ["chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"])
        -> Data
    {
        try! JSONSerialization.data(withJSONObject: ["name": name, "path": path, "type": "stdio", "allowed_origins": origins])
    }

    @Test func onlyValidAllowlistedManifestsAreMirrored() throws {
        let source = dir()
        let destination = dir()
        try manifest("com.apple.passwordmanager").write(to: source.appending(path: "com.apple.passwordmanager.json"))
        try manifest("com.evil.host").write(to: source.appending(path: "com.evil.host.json"))
        try manifest("com.1password.1password", path: "/nonexistent/helper").write(
            to: source.appending(path: "com.1password.1password.json"))
        try manifest("com.8bit.bitwarden", origins: ["chrome-extension://*/"]).write(to: source.appending(path: "com.8bit.bitwarden.json"))
        let mirrored = NativeMessagingHosts.mirror(into: destination, from: [source])
        #expect(mirrored == ["com.apple.passwordmanager"], "not allowlisted, missing binary, or wildcard origin: skipped")
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["com.apple.passwordmanager.json"])
    }

    @Test func aManifestMustNameItself() throws {
        let source = dir()
        try manifest("com.other").write(to: source.appending(path: "com.apple.passwordmanager.json"))
        #expect(NativeMessagingHosts.mirror(into: dir(), from: [source]).isEmpty)
    }
}

/// Manual probe: installs a store extension into a given store folder and profile.
/// `NERA_PROBE_STORE=<dir> NERA_PROBE_EXT=<id> NERA_PROBE_PROFILE=<uuid> swift test --filter StoreInstallIntoProbe`.
@Suite("Store install into probe")
struct StoreInstallIntoProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NERA_PROBE_STORE"] != nil))
    func install() async throws {
        let env = ProcessInfo.processInfo.environment
        let store = ExtensionStore(directory: URL(fileURLWithPath: env["NERA_PROBE_STORE"] ?? ""))
        store.profileID = env["NERA_PROBE_PROFILE"].flatMap(UUID.init(uuidString:))
        let ext = try await store.installFromWebStore(env["NERA_PROBE_EXT"] ?? "", chromiumMajor: 156)
        print("probe: installed \(ext.name) \(ext.version) popup \(ext.popupPath ?? "-") perms \(ext.permissions)")
    }
}
