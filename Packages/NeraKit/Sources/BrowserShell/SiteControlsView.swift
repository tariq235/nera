// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import Extensions
import Permissions
import SecurityPolicy
import SwiftUI

/// The site controls (the address pill's popover), laid out like Arc's: Share, Customize, Capture and Print; the
/// extensions; this site's settings (permissions, developer tools, engine); and whether the connection is secure.
struct SiteInfoView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
        @State private var openExtension: InstalledExtension?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            actions
            #if os(macOS)
                extensions
            #endif
            if let origin = model.currentSiteOrigin, let profile = model.state.currentProfile {
                Text("Settings").font(.system(size: 15, weight: .bold))
                VStack(spacing: 4) {
                    ForEach(PermissionPolicy.visibleKinds, id: \.self) { kind in
                        permissionRow(kind, origin: origin, profile: profile)
                    }
                    #if os(macOS)
                        row(
                            symbol: "hammer.fill", title: "Developer Tools",
                            value: model.state.settings.isDeveloperToolsEnabled ? "On" : "Off",
                            identifier: "siteInfo.devTools"
                        ) {
                            Button(model.state.settings.isDeveloperToolsEnabled ? "Turn Off" : "Turn On") {
                                model.setDeveloperTools(!model.state.settings.isDeveloperToolsEnabled)
                            }
                        }
                    #endif
                    engineRow
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("siteInfo.popover")
        #if os(macOS)
            .popover(item: $openExtension, arrowEdge: .trailing) { ext in ExtensionPopup(model: model, ext: ext) }
        #endif
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if let url = model.state.selectedTab?.url {
                ShareLink(item: url) { tile("square.and.arrow.up") }
                    .buttonStyle(.plain).help("Share").accessibilityLabel("Share").accessibilityIdentifier("siteInfo.share")
            }
            tileButton("paintbrush.pointed", "Customize Page", id: "siteInfo.siteStyle") {
                dismiss()
                model.isSiteStyleEditorPresented = true
            }
            .disabled(model.isPrivate)
            #if os(macOS)
                tileButton("camera", "Capture", id: "siteInfo.capture") {
                    dismiss()
                    model.startCapture()
                }
                tileButton("printer", "Print", id: "siteInfo.print") {
                    dismiss()
                    model.printPage()
                }
            #endif
        }
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .contentShape(Rectangle())
    }

    private func tileButton(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(symbol) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
    }

    // MARK: Extensions

    #if os(macOS)
        @ViewBuilder private var extensions: some View {
            if model.supportsExtensions, !model.isPrivate {
                let enabled: [InstalledExtension] = {
                    _ = model.extensionsRevision
                    return model.extensionStore.extensions.filter(\.isEnabled)
                }()
                Text("Extensions").font(.system(size: 15, weight: .bold))
                HStack(spacing: 8) {
                    ForEach(enabled.prefix(5)) { ext in
                        Button {
                            if ext.popupPath != nil { openExtension = ext }
                        } label: {
                            ExtensionIcon(model: model, ext: ext, size: 20)
                                .frame(width: 44, height: 40)
                                .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(ext.name)
                        .accessibilityLabel(ext.name)
                    }
                    SettingsLink {
                        Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                            .frame(width: 44, height: 40)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Add or manage extensions")
                    .accessibilityLabel("Manage Extensions")
                    .accessibilityIdentifier("siteInfo.extensions")
                }
            }
        }
    #endif

    // MARK: Settings rows

    /// A setting as Arc shows it: an icon in a circle, its name, and its value below; a click offers the choices.
    private func row<Choices: View>(
        symbol: String, title: String, value: String, identifier: String, @ViewBuilder choices: () -> Choices
    ) -> some View {
        Menu {
            choices()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.deepTone(for: model.displayedTheme)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(value).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityIdentifier(identifier)
    }

    private func permissionRow(_ kind: SitePermissionKind, origin: String, profile: Profile) -> some View {
        let setting = profile.sitePermission(origin: origin, kind: kind)
        let blocked = PermissionPolicy.isBlockedByDefault(kind, profile: profile)
        let value: String =
            switch setting {
            case .allow?: "Allowed"
            case .deny?: "Blocked"
            case nil: blocked ? "Blocked (default)" : "Ask (default)"
            }
        return row(symbol: kind.symbol, title: kind.title, value: value, identifier: "permission.\(kind.rawValue)") {
            Button(blocked ? "Block (Default)" : "Ask (Default)") { model.setSitePermission(origin: origin, kind: kind, setting: nil) }
            Button("Allow") { model.setSitePermission(origin: origin, kind: kind, setting: .allow) }
            Button("Block") { model.setSitePermission(origin: origin, kind: kind, setting: .deny) }
        }
    }

    @ViewBuilder private var engineRow: some View {
        if let site = SiteEngines.site(of: model.state.selectedTab?.url), let engine = model.currentSiteEngine {
            // Chromium can't play some video formats and DRM; WebKit can.
            let onWebKit = engine == .webKit
            row(symbol: "arrow.triangle.swap", title: "Engine", value: onWebKit ? "WebKit" : "Chromium", identifier: "siteInfo.engine") {
                Button(onWebKit ? "Open This Site with Chromium" : "Open This Site with WebKit") {
                    dismiss()
                    model.setEngine(onWebKit ? .chromium : .webKit, forSite: site)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            let insecure = DisplayURL.isInsecure(model.state.selectedTab?.url)
            Label(insecure ? "Not Secure" : "Secure", systemImage: insecure ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(insecure ? Color.orange : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(insecure ? "Information you send to this site can be read by others" : "The connection to this site is encrypted")
                .accessibilityIdentifier("siteInfo.connection")
            Spacer()
            Menu {
                Button("Reset Permissions for This Site") { model.resetSitePermissions() }
                    .accessibilityIdentifier("siteInfo.reset")
                #if os(macOS)
                    SettingsLink { Text("All Site Settings…") }
                #endif
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }
}
