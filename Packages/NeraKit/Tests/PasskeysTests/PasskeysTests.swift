// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import SecurityPolicy
import Testing

@testable import Passkeys

@Suite("WebAuthn options")
struct WebAuthnOptionsTests {
    let page = SecurityOrigin(scheme: "https", host: "login.example.com", port: nil)
    let challenge = #"{"$b64":"AAAAAAAAAAAAAAAAAAAAAA"}"#

    @Test func relyingPartyMustBeTheHostOrAParentDomain() throws {
        #expect(try WebAuthnOptions.relyingParty(nil, origin: page) == "login.example.com", "default: the page's host")
        #expect(try WebAuthnOptions.relyingParty("example.com", origin: page) == "example.com")
        #expect(try WebAuthnOptions.relyingParty("LOGIN.example.com", origin: page) == "login.example.com")
        for bad in ["evil.com", "ample.com", "com", "other.example.com", "xample.com"] {
            #expect(throws: WebAuthnOptions.Rejection.relyingPartyMismatch, "\(bad)") {
                try WebAuthnOptions.relyingParty(bad, origin: page)
            }
        }
        let uk = SecurityOrigin(scheme: "https", host: "shop.example.co.uk", port: nil)
        #expect(throws: WebAuthnOptions.Rejection.relyingPartyMismatch, "a public suffix") {
            try WebAuthnOptions.relyingParty("co.uk", origin: uk)
        }
        #expect(try WebAuthnOptions.relyingParty("example.co.uk", origin: uk) == "example.co.uk")
        let pages = SecurityOrigin(scheme: "https", host: "me.github.io", port: nil)
        #expect(throws: WebAuthnOptions.Rejection.relyingPartyMismatch, "hosting suffix") {
            try WebAuthnOptions.relyingParty("github.io", origin: pages)
        }
        let local = SecurityOrigin(scheme: "http", host: "localhost", port: 3000)
        #expect(try WebAuthnOptions.relyingParty("localhost", origin: local) == "localhost", "local development")
        let ip = SecurityOrigin(scheme: "https", host: "10.0.0.5", port: nil)
        #expect(throws: WebAuthnOptions.Rejection.relyingPartyMismatch) { try WebAuthnOptions.relyingParty("0.0.5", origin: ip) }
    }

    @Test func createOptionsParse() throws {
        let json = """
            {"challenge":\(challenge),"rp":{"name":"Example","id":"example.com"},
             "user":{"id":{"$b64":"dXNlcg"},"name":"me@example.com","displayName":"Me"},
             "pubKeyCredParams":[{"type":"public-key","alg":-7},{"type":"public-key","alg":-257}],
             "excludeCredentials":[{"type":"public-key","id":{"$b64":"AQID"}}],
             "authenticatorSelection":{"authenticatorAttachment":"platform","userVerification":"required"},"attestation":"none"}
            """
        let o = try WebAuthnOptions.create(json, origin: page)
        #expect(o.rpID == "example.com" && o.userName == "me@example.com" && o.userDisplayName == "Me")
        #expect(o.userID == Data("user".utf8) && o.challenge.count == 16 && o.excludeCredentials == [Data([1, 2, 3])])
        #expect(o.algorithms == [-7, -257] && o.attachment == "platform" && o.userVerification == "required")
    }

    @Test func getOptionsParse() throws {
        let json =
            #"{"challenge":"# + challenge + #","rpId":"example.com","allowCredentials":[{"type":"public-key","id":{"$b64":"AQID"}}]}"#
        let o = try WebAuthnOptions.get(json, origin: page)
        #expect(o.rpID == "example.com" && o.allowCredentials == [Data([1, 2, 3])] && o.userVerification == "preferred")
    }

    @Test func malformedOrHostileOptionsAreRefused() {
        let cases = [
            "not json", "[]", #"{"rpId":"example.com"}"#, #"{"challenge":{"$b64":"AA"}}"#,  // challenge too short
            #"{"challenge":"# + challenge + #","user":{"id":{"$b64":"dQ"}}}"#,  // no user name
        ]
        for json in cases.prefix(4) {
            #expect(throws: WebAuthnOptions.Rejection.self) { try WebAuthnOptions.get(json, origin: page) }
        }
        #expect(throws: WebAuthnOptions.Rejection.malformed) { try WebAuthnOptions.create(cases[4], origin: page) }
        let huge = #"{"challenge":"# + challenge + #","pad":"\#(String(repeating: "x", count: 300_000))"}"#
        #expect(throws: WebAuthnOptions.Rejection.malformed, "size cap") { try WebAuthnOptions.get(huge, origin: page) }
    }

    @Test func base64URLRoundTrips() {
        for bytes in [Data(), Data([0]), Data([0xfb, 0xff, 0xbf]), Data((0..<255).map { UInt8($0) })] {
            #expect(WebAuthnOptions.base64URL(WebAuthnOptions.base64URL(bytes)) == bytes)
            #expect(!WebAuthnOptions.base64URL(bytes).contains { "+/=".contains($0) })
        }
    }

    #if os(macOS)
        @MainActor
        @Test func withoutTheEntitlementPagesFailFastAndFallBack() async {
            let auth = SystemPasskeyAuthenticator(isEntitled: false)
            let request = WebAuthnRequestFixture.get
            #expect(await auth.perform(request) == .unavailable)
            #expect(await auth.perform(WebAuthnRequestFixture.available) == .success("false"))
        }
    #endif
}

enum WebAuthnRequestFixture {
    static let origin = SecurityOrigin(scheme: "https", host: "example.com", port: nil)
    static let get = WebAuthnRequest(
        kind: .get, optionsJSON: #"{"challenge":{"$b64":"AAAAAAAAAAAAAAAAAAAAAA"}}"#, origin: origin, topOrigin: origin)
    static let available = WebAuthnRequest(kind: .available, optionsJSON: "{}", origin: origin, topOrigin: origin)
}
