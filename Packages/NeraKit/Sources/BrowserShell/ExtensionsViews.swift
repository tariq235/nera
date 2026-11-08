// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import Extensions
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit

    /// An extension's icon from its installed folder, or a puzzle piece.
    struct ExtensionIcon: View {
        let model: AppModel
        let ext: InstalledExtension
        var size: CGFloat = 20

        var body: some View {
            if let path = ext.iconPath, let image = NSImage(contentsOf: model.extensionStore.folder(for: ext).appending(path: path)) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
            } else {
                Image(systemName: "puzzlepiece.extension.fill").frame(width: size, height: size).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Settings → Extensions: install from the Chrome Web Store or a file, enable, remove, permissions.
    struct ExtensionsSettingsView: View {
        @Bindable var model: AppModel
        @State private var link = ""
        @State private var isInstalling = false
        @State private var isPickingFile = false

        private var extensions: [InstalledExtension] {
            _ = model.extensionsRevision
            return model.extensionStore.extensions
        }

        var body: some View {
            Form {
                if !model.supportsExtensions {
                    Section {
                        Label("Extensions run in the Chromium engine, which isn't running.", systemImage: "exclamationmark.triangle")
                    }
                }
                if model.needsRelaunchForExtensions {
                    Section {
                        HStack {
                            Label("Relaunch Nera to apply extension changes.", systemImage: "arrow.clockwise.circle.fill")
                            Spacer()
                            Button("Relaunch Now") { model.relaunch() }.accessibilityIdentifier("extensions.relaunch")
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("Chrome Web Store link or extension ID", text: $link)
                            .accessibilityIdentifier("extensions.link")
                            .onSubmit(install)
                        Button(isInstalling ? "Installing…" : "Install", action: install)
                            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || isInstalling)
                            .accessibilityIdentifier("extensions.install")
                    }
                    HStack {
                        Button("Open Chrome Web Store") {
                            if let url = URL(string: "https://chromewebstore.google.com") { model.send(.tab(.open(url, .newTab))) }
                        }
                        Button("Install from File…") { isPickingFile = true }
                    }
                } header: {
                    Text("Add Extension")
                } footer: {
                    Text(
                        "Copy an extension's link from the Chrome Web Store and paste it here. Nera checks the developer's and the store's signatures before installing."
                    )
                    .foregroundStyle(.secondary)
                }
                Section("Installed") {
                    if extensions.isEmpty { Text("No extensions installed.").foregroundStyle(.secondary) }
                    ForEach(extensions) { ext in ExtensionRow(model: model, ext: ext) }
                }
                if model.state.profiles.count > 1, let current = model.extensionsProfileID {
                    Section {
                        Picker(
                            "Extensions run in",
                            selection: Binding(get: { current }, set: { model.setExtensionsProfile($0) })
                        ) {
                            ForEach(model.state.profiles) { Text($0.name).tag($0.id) }
                        }
                    } footer: {
                        Text("Nera's Chromium engine runs extensions in one profile for now.").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [UTType(filenameExtension: "crx") ?? .data]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    model.installExtension(fromFile: url)
                }
            }
        }

        private func install() {
            let input = link
            isInstalling = true
            Task {
                await model.installExtension(fromWebStore: input)
                isInstalling = false
                link = ""
            }
        }
    }

    private struct ExtensionRow: View {
        let model: AppModel
        let ext: InstalledExtension
        @State private var isConfirmingRemove = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ExtensionIcon(model: model, ext: ext, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ext.name).font(.headline)
                        Text("\(ext.version) · \(ext.source == .webStore ? "Chrome Web Store" : "From file")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(get: { ext.isEnabled }, set: { model.setExtension(ext.id, enabled: $0) }))
                        .labelsHidden()
                        .accessibilityLabel("\(ext.name) enabled")
                    Button(role: .destructive) {
                        isConfirmingRemove = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(ext.name)")
                    .accessibilityLabel("Remove \(ext.name)")
                }
                if !ext.summary.isEmpty { Text(ext.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                if ext.readsAllSites {
                    Label("Can read and change all your data on all websites", systemImage: "eye").font(.caption).foregroundStyle(.orange)
                }
                ForEach(ext.compatibilityNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .confirmationDialog("Remove \(ext.name)?", isPresented: $isConfirmingRemove) {
                Button("Remove", role: .destructive) { model.removeExtension(ext.id) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("extensions.row")
        }
    }

    /// The sidebar's Extensions button: enabled extensions with popups, each opening in a panel.
    struct ExtensionsButton: View {
        @Bindable var model: AppModel
        @State private var open: InstalledExtension?

        private var withPopups: [InstalledExtension] {
            _ = model.extensionsRevision
            return model.supportsExtensions ? model.extensionStore.extensions.filter { $0.isEnabled && $0.popupPath != nil } : []
        }

        var body: some View {
            if !withPopups.isEmpty {
                Menu {
                    ForEach(withPopups) { ext in
                        Button(ext.name) { open = ext }
                    }
                    Divider()
                    SettingsLink { Text("Manage Extensions…") }
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Extensions")
                .accessibilityLabel("Extensions")
                .accessibilityIdentifier("sidebar.extensions")
                .popover(item: $open, arrowEdge: .top) { ext in ExtensionPopup(model: model, ext: ext) }
            }
        }
    }

    /// An extension's popup page in a panel. Its requests (dialogs, downloads, new windows) are declined.
    struct ExtensionPopup: View {
        let model: AppModel
        let ext: InstalledExtension
        @State private var host = PopupHost()

        var body: some View {
            Group {
                if let page = host.page {
                    WebViewHost(page: page, isAccessible: true)
                } else {
                    Text("This extension's popup can't open.").foregroundStyle(.secondary).padding()
                }
            }
            .frame(width: 380, height: 520)
            .onAppear { host.page = model.makeExtensionPopup(ext, delegate: host) }
            .onDisappear {
                host.page?.close()
                host.page = nil
            }
        }
    }

    /// Delegate for popup pages: ignores events; requests are dropped, so their safe defaults apply.
    @MainActor
    final class PopupHost: WebPageDelegate {
        var page: (any WebPage)?
        func pageDidChangeState(_ page: any WebPage) {}
        func page(_ page: any WebPage, didEmit event: PageEvent) {}
        func page(_ page: any WebPage, didRequest request: PageRequest) {}
    }
#endif
