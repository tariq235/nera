// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
public import SecurityPolicy

/// A WebAuthn (passkey) request a page made, for engines that route WebAuthn through Nera (Chromium; WebKit
/// talks to the system itself). See docs/security/passkeys.md.
public struct WebAuthnRequest: Sendable, Equatable {
    /// What the page asked for.
    public enum Kind: String, Sendable {
        /// `navigator.credentials.create({publicKey})`.
        case create
        /// `navigator.credentials.get({publicKey})`.
        case get
        /// `PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()`.
        case available
    }

    /// The operation.
    public var kind: Kind
    /// The page's `publicKey` options as JSON; binary fields are `{"$b64": "<base64url>"}`. **Untrusted.**
    public var optionsJSON: String
    /// The requesting frame's origin, as the engine determined it (never what the page claims).
    public var origin: SecurityOrigin
    /// The top-level page's origin (differs for cross-origin iframes).
    public var topOrigin: SecurityOrigin

    /// Creates a request.
    public init(kind: Kind, optionsJSON: String, origin: SecurityOrigin, topOrigin: SecurityOrigin) {
        self.kind = kind
        self.optionsJSON = optionsJSON
        self.origin = origin
        self.topOrigin = topOrigin
    }
}

/// The answer to a ``WebAuthnRequest``.
public enum WebAuthnResult: Sendable, Equatable {
    /// The credential as JSON (base64url binary fields; see the shim), or `"true"`/`"false"` for `available`.
    case success(String)
    /// A DOMException name (`NotAllowedError`, `InvalidStateError`, `SecurityError`, …) and message.
    case failure(name: String, message: String)

    /// No authenticator: the page sees `NotAllowedError` at once and can fall back to passwords.
    public static let unavailable = WebAuthnResult.failure(
        name: "NotAllowedError", message: "Passkeys aren't available in this browser yet.")

    /// The failure's name (empty for success).
    public var name: String {
        if case .failure(let name, _) = self { return name }
        return ""
    }

    /// The failure's message (empty for success).
    public var message: String {
        if case .failure(_, let message) = self { return message }
        return ""
    }
}

/// Performs WebAuthn for engines that route it through Nera.
@MainActor
public protocol WebAuthenticator: AnyObject {
    /// Whether passkeys can work at all (e.g. the browser entitlement is present). When false, pages don't see
    /// `PublicKeyCredential`, so sites show their password sign-in.
    var isAvailable: Bool { get }

    /// Runs the request (showing the system's passkey UI when needed).
    func perform(_ request: WebAuthnRequest) async -> WebAuthnResult
}
