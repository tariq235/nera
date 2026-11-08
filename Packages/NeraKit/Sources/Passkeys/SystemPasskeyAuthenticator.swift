// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import EngineKit
public import Foundation
import SecurityPolicy

#if os(macOS)
    public import AppKit
    public import AuthenticationServices

    /// Passkeys and security keys through Apple's browser WebAuthn API (iCloud Keychain, phones, security keys;
    /// FEAT-027). Needs the `com.apple.developer.web-browser.public-key-credential` entitlement: without it
    /// the system refuses, and pages get `NotAllowedError` and fall back to passwords.
    @MainActor
    public final class SystemPasskeyAuthenticator: NSObject, WebAuthenticator {
        /// Whether this build carries the passkey entitlement (Info.plist `NeraPasskeysEntitled`, set by the
        /// entitled build configuration). Without it the system call can't succeed, so Nera doesn't try.
        public let isEntitled: Bool
        private var pending: CheckedContinuation<WebAuthnResult, Never>?
        private var pendingKind: WebAuthnRequest.Kind = .get

        /// Creates the authenticator.
        public init(isEntitled: Bool) {
            self.isEntitled = isEntitled
        }

        /// Whether this app build carries the passkey entitlement (Info.plist `NeraPasskeysEntitled`).
        public static var bundleIsEntitled: Bool {
            let value = Bundle.main.object(forInfoDictionaryKey: "NeraPasskeysEntitled")
            return (value as? Bool) ?? ((value as? String)?.uppercased() == "YES")
        }

        /// Passkeys work when the entitlement is present on macOS 14.4 or later.
        public var isAvailable: Bool {
            guard #available(macOS 14.4, *) else { return false }
            return isEntitled
        }

        /// Runs a page's request.
        public func perform(_ request: WebAuthnRequest) async -> WebAuthnResult {
            guard isEntitled, #available(macOS 14.4, *) else { return request.kind == .available ? .success("false") : .unavailable }
            guard pending == nil else { return .failure(name: "NotAllowedError", message: "Another passkey request is in progress.") }
            do {
                switch request.kind {
                case .available:
                    return .success(
                        ASAuthorizationWebBrowserPublicKeyCredentialManager().authorizationStateForPlatformCredentials == .denied
                            ? "false" : "true")
                case .create:
                    return await run(
                        .create, try registrationRequests(WebAuthnOptions.create(request.optionsJSON, origin: request.origin), request))
                case .get:
                    return await run(.get, try assertionRequests(WebAuthnOptions.get(request.optionsJSON, origin: request.origin), request))
                }
            } catch WebAuthnOptions.Rejection.relyingPartyMismatch {
                return .failure(name: "SecurityError", message: "The relying party ID is not valid for this page.")
            } catch {
                return .failure(name: "TypeError", message: "Invalid WebAuthn options.")
            }
        }

        @available(macOS 14.4, *)
        private func clientData(_ challenge: Data, _ request: WebAuthnRequest) -> ASPublicKeyCredentialClientData {
            var data = ASPublicKeyCredentialClientData(challenge: challenge, origin: request.origin.description)
            if request.topOrigin != request.origin {
                data.topOrigin = request.topOrigin.description
                data.crossOrigin = .crossOrigin
            }
            return data
        }

        @available(macOS 14.4, *)
        private func registrationRequests(_ o: WebAuthnOptions.Create, _ request: WebAuthnRequest) -> [ASAuthorizationRequest] {
            let data = clientData(o.challenge, request)
            var out: [ASAuthorizationRequest] = []
            if o.attachment != "cross-platform" {
                let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: o.rpID)
                    .createCredentialRegistrationRequest(clientData: data, name: o.userName, userID: o.userID)
                platform.displayName = o.userDisplayName
                platform.userVerificationPreference = .init(rawValue: o.userVerification)
                platform.excludedCredentials = o.excludeCredentials.map {
                    ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
                }
                out.append(platform)
            }
            if o.attachment != "platform" {
                let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: o.rpID)
                    .createCredentialRegistrationRequest(
                        clientData: data, displayName: o.userDisplayName, name: o.userName, userID: o.userID)
                key.credentialParameters = (o.algorithms.isEmpty ? [-7] : o.algorithms).map {
                    ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier(rawValue: $0))
                }
                key.userVerificationPreference = .init(rawValue: o.userVerification)
                key.attestationPreference = .init(rawValue: o.attestation)
                out.append(key)
            }
            return out
        }

        @available(macOS 14.4, *)
        private func assertionRequests(_ o: WebAuthnOptions.Get, _ request: WebAuthnRequest) -> [ASAuthorizationRequest] {
            let data = clientData(o.challenge, request)
            let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: o.rpID)
                .createCredentialAssertionRequest(clientData: data)
            platform.allowedCredentials = o.allowCredentials.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
            platform.userVerificationPreference = .init(rawValue: o.userVerification)
            let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: o.rpID)
                .createCredentialAssertionRequest(clientData: data)
            key.allowedCredentials = o.allowCredentials.map {
                ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                    credentialID: $0, transports: ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported)
            }
            key.userVerificationPreference = .init(rawValue: o.userVerification)
            return [platform, key]
        }

        private func run(_ kind: WebAuthnRequest.Kind, _ requests: [ASAuthorizationRequest]) async -> WebAuthnResult {
            await withCheckedContinuation { continuation in
                pending = continuation
                pendingKind = kind
                let controller = ASAuthorizationController(authorizationRequests: requests)
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        private func finish(_ result: WebAuthnResult) {
            pending?.resume(returning: result)
            pending = nil
        }

        /// The credential as the shim expects it (base64url binary fields).
        nonisolated static func json(_ credential: any ASAuthorizationCredential) -> String? {
            let b: (Data) -> String = WebAuthnOptions.base64URL
            var out: [String: Any] = [:]
            switch credential {
            case let c as ASAuthorizationPlatformPublicKeyCredentialRegistration:
                guard let attestation = c.rawAttestationObject else { return nil }
                out = [
                    "id": b(c.credentialID), "clientDataJSON": b(c.rawClientDataJSON), "attestationObject": b(attestation),
                    "authenticatorAttachment": "platform", "transports": ["internal", "hybrid"],
                ]
            case let c as ASAuthorizationSecurityKeyPublicKeyCredentialRegistration:
                guard let attestation = c.rawAttestationObject else { return nil }
                out = [
                    "id": b(c.credentialID), "clientDataJSON": b(c.rawClientDataJSON), "attestationObject": b(attestation),
                    "authenticatorAttachment": "cross-platform", "transports": ["usb", "nfc"],
                ]
            case let c as ASAuthorizationPlatformPublicKeyCredentialAssertion:
                out = [
                    "id": b(c.credentialID), "clientDataJSON": b(c.rawClientDataJSON), "authenticatorData": b(c.rawAuthenticatorData),
                    "signature": b(c.signature), "userHandle": b(c.userID), "authenticatorAttachment": "platform",
                ]
            case let c as ASAuthorizationSecurityKeyPublicKeyCredentialAssertion:
                out = [
                    "id": b(c.credentialID), "clientDataJSON": b(c.rawClientDataJSON), "authenticatorData": b(c.rawAuthenticatorData),
                    "signature": b(c.signature), "userHandle": b(c.userID), "authenticatorAttachment": "cross-platform",
                ]
            default:
                return nil
            }
            return (try? JSONSerialization.data(withJSONObject: out)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    extension SystemPasskeyAuthenticator: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        /// The system returned a credential.
        public nonisolated func authorizationController(
            controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            let json = Self.json(authorization.credential)
            MainActor.assumeIsolated {
                finish(json.map(WebAuthnResult.success) ?? .failure(name: "NotAllowedError", message: "Unexpected credential."))
            }
        }

        /// The user cancelled, or the system refused.
        public nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
            let code = (error as? ASAuthorizationError)?.code
            MainActor.assumeIsolated {
                // Matches what browsers report: cancel and "not allowed" look the same to the page (privacy).
                var name = "NotAllowedError"
                if #available(macOS 15.0, *), code == .matchedExcludedCredential { name = "InvalidStateError" }
                finish(.failure(name: name, message: "The operation either timed out or was not allowed."))
            }
        }

        /// The window the passkey sheet attaches to.
        public nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
        }
    }
#endif
