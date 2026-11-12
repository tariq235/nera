// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Permissions
import SecurityPolicy
import SwiftUI

extension SitePermissionKind {
    /// Name in settings ("Camera").
    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .location: "Location"
        case .notifications: "Notifications"
        case .clipboardRead: "Clipboard"
        case .motion: "Motion sensors"
        }
    }

    /// SF Symbol.
    var symbol: String {
        switch self {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        case .location: "location.fill"
        case .notifications: "bell.fill"
        case .clipboardRead: "doc.on.clipboard"
        case .motion: "gyroscope"
        }
    }

    /// The default's "block" wording ("Don't allow sites to use your camera").
    var blockAllTitle: String {
        switch self {
        case .camera: "Don't allow sites to use your camera"
        case .microphone: "Don't allow sites to use your microphone"
        case .location: "Don't allow sites to see your location"
        case .notifications: "Don't allow sites to send notifications"
        case .clipboardRead: "Don't allow sites to read your clipboard"
        case .motion: "Don't allow sites to use motion sensors"
        }
    }
}

/// Ask / Allow / Block for one permission of one site.
struct PermissionPicker: View {
    let kind: SitePermissionKind
    let setting: SitePermissionSetting?
    let blockedByDefault: Bool
    let change: (SitePermissionSetting?) -> Void

    var body: some View {
        Picker(selection: Binding(get: { setting }, set: { change($0) })) {
            Text(blockedByDefault ? "Block (default)" : "Ask (default)").tag(SitePermissionSetting?.none)
            Text("Allow").tag(SitePermissionSetting?.some(.allow))
            Text("Block").tag(SitePermissionSetting?.some(.deny))
        } label: {
            Label(kind.title, systemImage: kind.symbol)
        }
        .accessibilityIdentifier("permission.\(kind.rawValue)")
    }
}

/// Settings → Site Settings: profile-wide defaults, and every site with saved choices.
struct SiteSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let profile = model.state.currentProfile {
            Form {
                Section {
                    ForEach(PermissionPolicy.visibleKinds, id: \.self) { kind in
                        Toggle(
                            isOn: Binding(
                                get: { PermissionPolicy.isBlockedByDefault(kind, profile: profile) },
                                set: { model.setPermissionBlockedByDefault(kind, $0) })
                        ) {
                            Label(kind.blockAllTitle, systemImage: kind.symbol)
                        }
                        .accessibilityIdentifier("defaults.\(kind.rawValue)")
                    }
                } header: {
                    Text("Defaults for \(profile.name)")
                } footer: {
                    Text("When off, sites ask first. Sites you allow below are exceptions.").foregroundStyle(.secondary)
                }

                Section {
                    let chosen = (profile.siteEngines ?? [:]).sorted { $0.key < $1.key }
                    ForEach(chosen, id: \.key) { site, engine in
                        HStack {
                            Text(site)
                            Spacer()
                            Text(engine == .webKit ? "WebKit" : "Chromium").foregroundStyle(.secondary)
                            Button {
                                model.setEngine(nil, forSite: site)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Back to the default engine")
                            .accessibilityLabel("Remove engine choice for \(site)")
                        }
                    }
                    Text("Streaming services (Netflix, Disney+, Prime Video, Spotify and others) always open with WebKit.")
                        .font(.callout).foregroundStyle(.secondary)
                } header: {
                    Text("Engines")
                } footer: {
                    Text(
                        "Nera uses Chromium, except for sites listed here. WebKit plays video formats and protected streams Chromium can't."
                    )
                    .foregroundStyle(.secondary)
                }

                let sites = PermissionPolicy.sites(in: profile)
                Section("Sites") {
                    if sites.isEmpty {
                        Text("No sites have asked for permissions yet.").foregroundStyle(.secondary)
                    }
                    ForEach(sites, id: \.origin) { site in
                        DisclosureGroup {
                            ForEach(PermissionPolicy.visibleKinds, id: \.self) { kind in
                                PermissionPicker(
                                    kind: kind, setting: site.settings[kind],
                                    blockedByDefault: PermissionPolicy.isBlockedByDefault(kind, profile: profile)
                                ) { model.setSitePermission(origin: site.origin, kind: kind, setting: $0) }
                            }
                            Button("Remove All Permissions for This Site", role: .destructive) {
                                model.resetSitePermissions(origin: site.origin)
                            }
                        } label: {
                            HStack {
                                Text(PermissionPolicy.displayName(site.origin))
                                Spacer()
                                ForEach(site.settings.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                                    Image(systemName: kind.symbol)
                                        .foregroundStyle(site.settings[kind] == .allow ? Color.green : Color.red)
                                        .help("\(kind.title): \(site.settings[kind] == .allow ? "allowed" : "blocked")")
                                }
                            }
                        }
                        .accessibilityIdentifier("siteSettings.site")
                    }
                    if !sites.isEmpty {
                        Button("Reset All Sites", role: .destructive) { model.resetSitePermissions(allSites: true) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
