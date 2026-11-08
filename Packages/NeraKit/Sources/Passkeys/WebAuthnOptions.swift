// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import SecurityPolicy

/// Parsing and validation of a page's WebAuthn options (pure; unit-tested). Input is untrusted page data.
public enum WebAuthnOptions {
    /// Why a request was refused before reaching the system.
    public enum Rejection: Error, Equatable, Sendable {
        /// The options aren't valid JSON or miss required fields.
        case malformed
        /// `rp.id` / `rpId` isn't the origin's host or one of its parent domains (or is a public suffix).
        case relyingPartyMismatch
    }

    /// A registration (`create`).
    public struct Create: Equatable, Sendable {
        /// Relying party ID (validated).
        public var rpID: String
        /// Challenge from the site.
        public var challenge: Data
        /// User handle.
        public var userID: Data
        /// Account name (e.g. email).
        public var userName: String
        /// Display name.
        public var userDisplayName: String
        /// Credentials the site already has for this user.
        public var excludeCredentials: [Data]
        /// `required` / `preferred` / `discouraged`.
        public var userVerification: String
        /// `platform`, `cross-platform`, or nil for either.
        public var attachment: String?
        /// `none` / `indirect` / `direct` / `enterprise`.
        public var attestation: String
        /// Algorithms the site accepts (COSE IDs).
        public var algorithms: [Int]
    }

    /// An assertion (`get`).
    public struct Get: Equatable, Sendable {
        /// Relying party ID (validated).
        public var rpID: String
        /// Challenge from the site.
        public var challenge: Data
        /// Credentials the site accepts (empty: any discoverable passkey).
        public var allowCredentials: [Data]
        /// `required` / `preferred` / `discouraged`.
        public var userVerification: String
    }

    /// Parses `create` options for a page at `origin`.
    public static func create(_ json: String, origin: SecurityOrigin) throws -> Create {
        let o = try object(json)
        let rp = o["rp"] as? [String: Any] ?? [:]
        let user = o["user"] as? [String: Any] ?? [:]
        guard let challenge = binary(o["challenge"]), let userID = binary(user["id"]), let name = user["name"] as? String,
            (1...64).contains(userID.count), challenge.count >= 16
        else { throw Rejection.malformed }
        let selection = o["authenticatorSelection"] as? [String: Any] ?? [:]
        return Create(
            rpID: try relyingParty(rp["id"] as? String, origin: origin), challenge: challenge, userID: userID, userName: name,
            userDisplayName: user["displayName"] as? String ?? name,
            excludeCredentials: (o["excludeCredentials"] as? [[String: Any]] ?? []).compactMap { binary($0["id"]) },
            userVerification: selection["userVerification"] as? String ?? "preferred",
            attachment: selection["authenticatorAttachment"] as? String, attestation: o["attestation"] as? String ?? "none",
            algorithms: (o["pubKeyCredParams"] as? [[String: Any]] ?? []).compactMap { $0["alg"] as? Int })
    }

    /// Parses `get` options for a page at `origin`.
    public static func get(_ json: String, origin: SecurityOrigin) throws -> Get {
        let o = try object(json)
        guard let challenge = binary(o["challenge"]), challenge.count >= 16 else { throw Rejection.malformed }
        return Get(
            rpID: try relyingParty(o["rpId"] as? String, origin: origin), challenge: challenge,
            allowCredentials: (o["allowCredentials"] as? [[String: Any]] ?? []).compactMap { binary($0["id"]) },
            userVerification: o["userVerification"] as? String ?? "preferred")
    }

    /// The relying party ID to use: the requested one if it's the origin's host or a parent domain of it (not
    /// a public suffix), else a rejection. No requested ID means the origin's host (WebAuthn's default).
    public static func relyingParty(_ requested: String?, origin: SecurityOrigin) throws -> String {
        let host = origin.host.lowercased()
        guard let requested = requested?.lowercased(), !requested.isEmpty else { return host }
        guard requested == host || host.hasSuffix("." + requested) else { throw Rejection.relyingPartyMismatch }
        // An IP address can only be its own RP ID; a domain must not be a public suffix.
        if requested != host, host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { throw Rejection.relyingPartyMismatch }
        guard requested.contains("."), !publicSuffixes.contains(requested) else {
            if requested == host, host == "localhost" { return host }
            throw Rejection.relyingPartyMismatch
        }
        return requested
    }

    /// Multi-label public suffixes where registrable domains are common. Single labels (`com`, `uk`) are refused
    /// by the dot check. Not the full Public Suffix List; the system authenticator validates as well.
    static let publicSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "co.nz", "org.nz", "net.nz", "co.in", "net.in", "org.in", "co.za",
        "org.za", "com.br", "net.br", "org.br", "com.cn", "net.cn", "org.cn", "com.hk", "com.sg", "com.tw", "com.mx", "com.tr",
        "co.kr", "or.kr", "com.ar", "com.my", "com.pk", "com.sa", "com.eg", "co.il", "co.id", "com.ph", "com.vn", "com.ng",
        "github.io", "gitlab.io", "herokuapp.com", "vercel.app", "netlify.app", "pages.dev", "web.app", "firebaseapp.com",
        "azurewebsites.net", "cloudfront.net", "appspot.com", "blogspot.com", "s3.amazonaws.com",
    ]

    static func object(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8), data.count < 256 * 1024,
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw Rejection.malformed }
        return o
    }

    /// `{"$b64": "<base64url>"}` → bytes (how the shim sends ArrayBuffers).
    static func binary(_ value: Any?) -> Data? {
        guard let text = (value as? [String: Any])?["$b64"] as? String else { return nil }
        return base64URL(text)
    }

    /// Decodes base64url (no padding).
    public static func base64URL(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }

    /// Encodes base64url (no padding).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
