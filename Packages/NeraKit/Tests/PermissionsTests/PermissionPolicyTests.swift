// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import Foundation
import SecurityPolicy
import Testing

@testable import Permissions

/// Per-site permission manager (SEC-040): who gets asked, what's remembered, and where.
@Suite("Permission manager")
struct PermissionPolicyTests {
    let site = SecurityOrigin(scheme: "https", host: "meet.example", port: nil)
    let profileA = UUID()
    let profileB = UUID()

    func state(_ actions: [Action] = []) -> BrowserState {
        let a = profileA
        var s = BrowserState.initial(uuid: { a })
        s.profiles.append(Profile(id: profileB, name: "Work"))
        for action in actions { _ = Reducer.reduce(&s, action, .test) }
        return s
    }

    @Test func insecureAndOpaqueOriginsAreDeniedWithoutAsking() {
        let http = SecurityOrigin(scheme: "http", host: "meet.example", port: nil)
        #expect(PermissionPolicy.automaticDecision(origin: http, kinds: [.camera], profile: nil) == .deny)
        #expect(PermissionPolicy.automaticDecision(origin: .opaque, kinds: [.camera], profile: nil) == .deny)
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [], profile: nil) == .deny)
        let localhost = SecurityOrigin(scheme: "http", host: "localhost", port: 3000)
        #expect(PermissionPolicy.automaticDecision(origin: localhost, kinds: [.camera], profile: nil) == nil, "loopback is secure: ask")
    }

    @Test func unknownSitesAreAsked() {
        let s = state()
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [.camera, .microphone], profile: s.profiles[0]) == nil)
    }

    @Test func rememberedAnswersApplyAndOneDenialDenies() {
        let allowBoth = PermissionPolicy.remember(.grant, origin: site, kinds: [.camera, .microphone], profileID: profileA)
        var s = state(allowBoth)
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [.camera, .microphone], profile: s.profiles[0]) == .grant)
        #expect(
            PermissionPolicy.automaticDecision(origin: site, kinds: [.camera, .location], profile: s.profiles[0]) == nil, "partial: ask")
        _ = Reducer.reduce(&s, PermissionPolicy.remember(.deny, origin: site, kinds: [.microphone], profileID: profileA)[0], .test)
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [.camera, .microphone], profile: s.profiles[0]) == .deny)
    }

    @Test func decisionsBelongToOneProfileAndOneOrigin() {
        let s = state(PermissionPolicy.remember(.grant, origin: site, kinds: [.location], profileID: profileA))
        let other = SecurityOrigin(scheme: "https", host: "evil.example", port: nil)
        #expect(
            PermissionPolicy.automaticDecision(origin: site, kinds: [.location], profile: s.profiles[1]) == nil,
            "profile B never inherits A")
        #expect(PermissionPolicy.automaticDecision(origin: other, kinds: [.location], profile: s.profiles[0]) == nil)
        let port = SecurityOrigin(scheme: "https", host: "meet.example", port: 8443)
        #expect(
            PermissionPolicy.automaticDecision(origin: port, kinds: [.location], profile: s.profiles[0]) == nil,
            "port is part of the origin")
    }

    @Test func decisionsCanBeRevoked() {
        var s = state(
            PermissionPolicy.remember(.grant, origin: site, kinds: [.camera, .notifications], profileID: profileA)
                + PermissionPolicy.remember(
                    .grant, origin: SecurityOrigin(scheme: "https", host: "b.example", port: nil), kinds: [.camera], profileID: profileA))
        _ = Reducer.reduce(
            &s, .library(.setSitePermission(profileID: profileA, origin: "https://meet.example", kind: .camera, setting: nil)), .test)
        #expect(s.profiles[0].sitePermission(origin: "https://meet.example", kind: .camera) == nil)
        #expect(s.profiles[0].sitePermission(origin: "https://meet.example", kind: .notifications) == .allow)
        _ = Reducer.reduce(&s, .library(.resetSitePermissions(profileID: profileA, origin: "https://meet.example")), .test)
        #expect(s.profiles[0].sitePermission(origin: "https://meet.example", kind: .notifications) == nil)
        #expect(s.profiles[0].sitePermission(origin: "https://b.example", kind: .camera) == .allow, "other sites kept")
        _ = Reducer.reduce(&s, .library(.resetSitePermissions(profileID: profileA, origin: nil)), .test)
        #expect(s.profiles[0].sitePermissions == nil)
    }

    @Test func everyEngineKindMapsToALibraryKind() {
        for kind in PermissionKind.allCases { _ = PermissionPolicy.siteKind(kind) }
        #expect(PermissionPolicy.siteKind(.clipboardRead) == .clipboardRead)
    }

    @Test func librariesWithoutSitePermissionsStillDecode() throws {
        let json = #"{"id":"6D7B1F2E-6C1B-4E2A-9F0B-1A2B3C4D5E6F","name":"Personal","favorites":[]}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.sitePermissions == nil)
        #expect(profile.sitePermission(origin: "https://x", kind: .camera) == nil)
    }
}

extension ReducerEnvironment {
    static let test = ReducerEnvironment(now: { Date(timeIntervalSince1970: 0) }, uuid: { UUID() })
}

/// profile-wide defaults and the site list behind Site Settings.
@Suite("Site settings")
struct SiteSettingsTests {
    let profileID = UUID()
    let site = SecurityOrigin(scheme: "https", host: "meet.example", port: nil)

    func profile(_ actions: [LibraryAction]) -> Profile {
        let id = profileID
        var s = BrowserState.initial(uuid: { id })
        for a in actions { _ = Reducer.reduce(&s, .library(a), .test) }
        return s.profiles[0]
    }

    @Test func blockingByDefaultDeniesWithoutAskingButSitesCanBeAllowed() {
        let blocked = profile([
            .setSitePermission(profileID: profileID, origin: SitePermission.allSites, kind: .notifications, setting: .deny)
        ])
        #expect(PermissionPolicy.isBlockedByDefault(.notifications, profile: blocked))
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [.notifications], profile: blocked) == .deny)
        #expect(PermissionPolicy.automaticDecision(origin: site, kinds: [.camera], profile: blocked) == nil, "other kinds still ask")
        let exception = profile([
            .setSitePermission(profileID: profileID, origin: SitePermission.allSites, kind: .notifications, setting: .deny),
            .setSitePermission(profileID: profileID, origin: "https://meet.example", kind: .notifications, setting: .allow),
        ])
        #expect(
            PermissionPolicy.automaticDecision(origin: site, kinds: [.notifications], profile: exception) == .grant, "a site exception wins"
        )
    }

    @Test func resettingAllSitesKeepsTheDefaults() {
        let p = profile([
            .setSitePermission(profileID: profileID, origin: SitePermission.allSites, kind: .location, setting: .deny),
            .setSitePermission(profileID: profileID, origin: "https://a.example", kind: .camera, setting: .allow),
            .resetSitePermissions(profileID: profileID, origin: nil),
        ])
        #expect(PermissionPolicy.isBlockedByDefault(.location, profile: p))
        #expect(PermissionPolicy.sites(in: p).isEmpty)
    }

    @Test func sitesAreGroupedAndSortedForDisplay() {
        let p = profile([
            .setSitePermission(profileID: profileID, origin: "https://zoom.example", kind: .camera, setting: .allow),
            .setSitePermission(profileID: profileID, origin: "https://meet.example", kind: .camera, setting: .deny),
            .setSitePermission(profileID: profileID, origin: "https://meet.example", kind: .microphone, setting: .allow),
            .setSitePermission(profileID: profileID, origin: SitePermission.allSites, kind: .camera, setting: .deny),
        ])
        let sites = PermissionPolicy.sites(in: p)
        #expect(sites.map(\.origin) == ["https://meet.example", "https://zoom.example"])
        #expect(sites[0].settings == [.camera: .deny, .microphone: .allow])
        #expect(PermissionPolicy.displayName("https://meet.example") == "meet.example")
        #expect(PermissionPolicy.displayName("http://localhost:3000") == "http://localhost:3000")
    }
}
