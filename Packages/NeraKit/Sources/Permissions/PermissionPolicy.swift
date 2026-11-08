// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import EngineKit
public import Foundation
public import SecurityPolicy

/// Nera's per-site permission rules (SEC-040), engine-neutral.
///
/// - Only secure origins (HTTPS or loopback) can be granted anything; others are denied without asking.
/// - Decisions are remembered per profile and origin and can be revoked
///   (`LibraryAction.setSitePermission` / `resetSitePermissions`).
/// - A request for several kinds (camera + microphone) is granted from memory only if every kind is allowed;
///   one remembered denial denies it. Anything else is asked.
public enum PermissionPolicy {
    /// The library's name for an engine permission kind.
    public static func siteKind(_ kind: PermissionKind) -> SitePermissionKind {
        switch kind {
        case .camera: .camera
        case .microphone: .microphone
        case .motion: .motion
        case .location: .location
        case .notifications: .notifications
        case .clipboardRead: .clipboardRead
        }
    }

    /// The key remembered decisions are stored under: `scheme://host[:port]`.
    public static func originKey(_ origin: SecurityOrigin) -> String { origin.description }

    /// What happens to a request before anyone is asked: an automatic answer, or `nil` to ask the user.
    public static func automaticDecision(
        origin: SecurityOrigin, kinds: Set<PermissionKind>, profile: Profile?
    ) -> PermissionDecision? {
        guard !origin.isOpaque, origin.isSecure, !kinds.isEmpty else { return .deny }
        guard let profile else { return nil }
        let remembered = kinds.map { effectiveSetting(origin: originKey(origin), kind: siteKind($0), profile: profile) }
        if remembered.contains(.deny) { return .deny }
        if remembered.allSatisfy({ $0 == .allow }) { return .grant }
        return nil
    }

    /// The decision that applies to a site: its own remembered answer, else the profile's "don't allow" default.
    public static func effectiveSetting(origin: String, kind: SitePermissionKind, profile: Profile) -> SitePermissionSetting? {
        profile.sitePermission(origin: origin, kind: kind)
            ?? (profile.sitePermission(origin: SitePermission.allSites, kind: kind) == .deny ? .deny : nil)
    }

    /// Whether the profile blocks `kind` for every site without asking (sites can still be allowed one by one).
    public static func isBlockedByDefault(_ kind: SitePermissionKind, profile: Profile) -> Bool {
        profile.sitePermission(origin: SitePermission.allSites, kind: kind) == .deny
    }

    /// The profile's remembered decisions grouped by site, sites sorted by name (defaults excluded).
    public static func sites(in profile: Profile) -> [(origin: String, settings: [SitePermissionKind: SitePermissionSetting])] {
        let entries = (profile.sitePermissions ?? []).filter { $0.origin != SitePermission.allSites }
        let grouped = Dictionary(grouping: entries, by: \.origin)
        return grouped.keys.sorted { displayName($0) < displayName($1) }.map { origin in
            (origin, Dictionary(grouped[origin, default: []].map { ($0.kind, $0.setting) }, uniquingKeysWith: { _, b in b }))
        }
    }

    /// `https://www.example.com` → `www.example.com` (non-default schemes and ports kept).
    public static func displayName(_ origin: String) -> String {
        origin.hasPrefix("https://") ? String(origin.dropFirst("https://".count)) : origin
    }

    /// Kinds that appear in site settings on this platform, in display order.
    public static var visibleKinds: [SitePermissionKind] {
        #if os(iOS)
            [.camera, .microphone, .location, .notifications, .clipboardRead, .motion]
        #else
            [.camera, .microphone, .location, .notifications, .clipboardRead]
        #endif
    }

    /// Actions that remember the user's answer for every requested kind.
    public static func remember(
        _ decision: PermissionDecision, origin: SecurityOrigin, kinds: Set<PermissionKind>, profileID: UUID
    ) -> [Action] {
        let setting: SitePermissionSetting = decision == .grant ? .allow : .deny
        return kinds.sorted { $0.rawValue < $1.rawValue }.map {
            .library(.setSitePermission(profileID: profileID, origin: originKey(origin), kind: siteKind($0), setting: setting))
        }
    }
}
