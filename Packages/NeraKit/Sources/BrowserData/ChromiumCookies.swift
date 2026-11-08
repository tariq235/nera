// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CommonCrypto
public import Foundation
import SQLite3

#if os(macOS)
    import Security
#endif

/// A website cookie read from another browser: what keeps the user signed in to sites.
public struct ImportedCookie: Sendable, Hashable {
    /// The cookie's domain as the browser stored it (a leading dot means it's sent to subdomains too).
    public var domain: String
    /// Name.
    public var name: String
    /// Value (a secret: never logged or written anywhere but the engine's cookie store).
    public var value: String
    /// Path.
    public var path: String
    /// When it expires; `nil` for a session cookie.
    public var expires: Date?
    /// Sent only over HTTPS.
    public var isSecure: Bool
    /// Hidden from page scripts.
    public var isHTTPOnly: Bool
    /// SameSite: `nil` unspecified, or "None", "Lax", "Strict".
    public var sameSite: String?

    /// Creates a cookie.
    public init(
        domain: String, name: String, value: String, path: String, expires: Date?, isSecure: Bool, isHTTPOnly: Bool, sameSite: String?
    ) {
        self.domain = domain
        self.name = name
        self.value = value
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
    }

    /// The host without the leading dot of a domain cookie.
    public var host: String { domain.hasPrefix(".") ? String(domain.dropFirst()) : domain }
}

/// Why sign-ins couldn't be read.
public enum SignInImportError: Error, Equatable, Sendable {
    /// The user didn't allow access to the browser's key in the Keychain (or it doesn't exist).
    case keyUnavailable
    /// The browser has no cookie database.
    case noCookies
}

/// Reads a Chromium-family browser's cookies (Chrome, Arc, Brave, Edge) on macOS. Their values are encrypted
/// with a key kept in the login Keychain under "<Browser> Safe Storage"; macOS asks the user before Nera
/// can read it. Everything stays in memory and goes straight to Nera's engine.
public enum ChromiumCookies {
    /// The Keychain item holding the browser's cookie key.
    public static func keychainItem(for source: ImportSource) -> (service: String, account: String)? {
        switch source {
        case .chrome: ("Chrome Safe Storage", "Chrome")
        case .arc: ("Arc Safe Storage", "Arc")  // naming: import-reference
        case .brave: ("Brave Safe Storage", "Brave")
        case .edge: ("Microsoft Edge Safe Storage", "Microsoft Edge")
        default: nil
        }
    }

    /// The browser's cookie database (newer versions keep it in `Network/`).
    public static func databaseURL(inProfile profile: URL) -> URL? {
        [profile.appending(path: "Network/Cookies"), profile.appending(path: "Cookies")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    #if os(macOS)
        /// Reads the browser's cookies, asking macOS for its key (the user sees a Keychain prompt).
        public static func read(from source: ImportSource, now: Date = Date()) throws -> [ImportedCookie] {
            guard let item = keychainItem(for: source), let profile = source.dataDirectory else { throw SignInImportError.noCookies }
            guard let database = databaseURL(inProfile: profile) else { throw SignInImportError.noCookies }
            let password = try keychainPassword(service: item.service, account: item.account)
            return try read(database: database, key: derivedKey(password: password), now: now)
        }

        /// The password stored in a generic Keychain item. macOS shows the user an access prompt.
        static func keychainPassword(service: String, account: String) throws -> Data {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
                throw SignInImportError.keyUnavailable
            }
            return data
        }
    #endif

    /// Chromium's macOS cookie key: PBKDF2-HMAC-SHA1 of the Keychain password, "saltysalt", 1003 rounds, 16 bytes.
    public static func derivedKey(password: Data) -> Data {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        _ = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                    salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128)
            }
        }
        return key
    }

    /// Reads every unexpired cookie from a Chromium cookie database.
    public static func read(database: URL, key: Data, now: Date = Date()) throws -> [ImportedCookie] {
        let snapshot = try SQLiteSnapshot(of: database)
        let meta = try? SQLiteSnapshot(of: database).rows("SELECT value FROM meta WHERE key = 'version'") { Int($0.text(0) ?? "") }
        let version = meta?.first ?? 0
        return try snapshot.rows(
            "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires FROM cookies"
        ) { row in
            guard let host = row.text(0), let name = row.text(1), !host.isEmpty else { return nil }
            let expires = row.int(9) != 0 ? chromiumDate(row.int(5)) : nil
            if let expires, expires <= now { return nil }
            let value: String
            if let plain = row.text(2), !plain.isEmpty {
                value = plain
            } else if let blob = row.blob(3), let decrypted = decrypt(blob, key: key, hasDomainHash: version >= 24) {
                value = decrypted
            } else {
                return nil
            }
            return ImportedCookie(
                domain: host, name: name, value: value, path: row.text(4) ?? "/", expires: expires, isSecure: row.int(6) != 0,
                isHTTPOnly: row.int(7) != 0, sameSite: sameSite(row.int(8)))
        }
    }

    /// Decrypts a "v10" value: AES-128-CBC, an IV of 16 spaces, PKCS#7 padding. Databases from version 24 on
    /// start the plaintext with a 32-byte SHA-256 of the cookie's domain.
    static func decrypt(_ blob: Data, key: Data, hasDomainHash: Bool) -> String? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else { return nil }
        let cipher = blob.dropFirst(3)
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        var length = 0
        let capacity = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            cipher.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv, inBytes.baseAddress, cipher.count, outBytes.baseAddress, capacity, &length)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = out.prefix(length)
        if hasDomainHash {
            guard plain.count >= 32 else { return nil }
            plain = plain.dropFirst(32)
        }
        return String(data: plain, encoding: .utf8)
    }

    /// Chromium stores times as microseconds since 1601-01-01 UTC.
    static func chromiumDate(_ microseconds: Int) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600)
    }

    private static func sameSite(_ value: Int) -> String? {
        switch value {
        case 0: "None"
        case 1: "Lax"
        case 2: "Strict"
        default: nil
        }
    }
}
