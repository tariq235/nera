// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import SwiftUI

/// Settings › Links: where links from other apps open (rules first, then the default) and Peek.
struct LinksSettingsView: View {
    @Bindable var model: AppModel
    @State private var pattern = ""
    @State private var spaceID: UUID?

    var body: some View {
        Form {
            Section {
                Picker("Open links from other apps in", selection: externalLinks) {
                    Text("A Little Window").tag(ExternalLinkTarget.littleWindow)
                    Text("A new tab").tag(ExternalLinkTarget.currentSpace)
                }
                .accessibilityIdentifier("links.external")
            } header: {
                Text("Links from Other Apps")
            } footer: {
                Text("A Little Window is a small window of its own: read, then close it or press ⌘O to keep it as a tab.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(model.state.settings.linkRoutes) { route in
                    HStack {
                        Text(route.pattern).font(.body.monospaced())
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(spaceName(route.spaceID)).foregroundStyle(spaceExists(route.spaceID) ? .primary : .secondary)
                        Spacer()
                        Button(role: .destructive) {
                            model.send(.library(.removeLinkRoute(route.id)))
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this rule")
                        .accessibilityLabel("Remove rule for \(route.pattern)")
                    }
                }
                HStack {
                    TextField("Site", text: $pattern, prompt: Text("figma.com or github.com/nera"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                        .accessibilityIdentifier("links.pattern")
                    Picker("Space", selection: $spaceID) {
                        ForEach(model.state.spaces) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    Button("Add", action: add)
                        .disabled(LinkRoute.normalize(pattern).isEmpty || spaceID == nil)
                        .accessibilityIdentifier("links.add")
                }
            } header: {
                Text("Link Rules")
            } footer: {
                Text(
                    "Links from other apps that match a rule open in its Space, whatever the setting above. A site covers its subdomains; add a path to be more specific."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Open links from Favorites and pinned tabs in Peek",
                    isOn: Binding(get: { model.state.settings.peekLinks }, set: { model.send(.library(.setPeekLinks($0))) })
                )
                .accessibilityIdentifier("links.peek")
            } header: {
                Text("Peek")
            } footer: {
                Text("Links they open in a new tab float over the page instead, so your tabs stay tidy. ⌘O keeps one as a tab.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if spaceID == nil { spaceID = model.state.selectedSpaceID } }
    }

    private var externalLinks: Binding<ExternalLinkTarget> {
        Binding(get: { model.state.settings.externalLinks }, set: { model.send(.library(.setExternalLinks($0))) })
    }

    private func spaceExists(_ id: UUID) -> Bool { model.state.spaces.contains { $0.id == id } }

    private func spaceName(_ id: UUID) -> String { model.state.spaces.first { $0.id == id }?.title ?? "Deleted Space" }

    private func add() {
        guard let spaceID, !LinkRoute.normalize(pattern).isEmpty else { return }
        model.send(.library(.addLinkRoute(pattern: pattern, spaceID: spaceID)))
        pattern = ""
    }
}
