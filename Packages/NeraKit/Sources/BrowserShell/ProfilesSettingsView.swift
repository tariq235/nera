// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import SwiftUI

/// Settings → Profiles: each profile has its own cookies, logins, site settings, history and Favorites.
struct ProfilesSettingsView: View {
    @Bindable var model: AppModel
    @State private var newName = ""
    @State private var pendingDelete: Profile?

    var body: some View {
        Form {
            Section {
                ForEach(model.state.profiles) { profile in
                    ProfileRow(model: model, profile: profile) { pendingDelete = profile }
                }
            } footer: {
                Text(
                    "Each profile keeps its own cookies and logins, site permissions, history and Favorites. Spaces belong to one profile; move a Space from its context menu."
                )
                .foregroundStyle(.secondary)
            }
            Section("New Profile") {
                HStack {
                    TextField("Name (e.g. Work, School)", text: $newName)
                        .accessibilityIdentifier("profiles.newName")
                        .onSubmit(create)
                    Button("Add", action: create)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("profiles.add")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete the profile “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete Profile and Its Data", role: .destructive) {
                if let profile = pendingDelete { model.send(.library(.deleteProfile(profile.id))) }
                pendingDelete = nil
            }
        } message: {
            let spaces = pendingDelete.map { model.spaceCount(for: $0.id) } ?? 0
            Text(
                "Its \(spaces) Space\(spaces == 1 ? "" : "s"), Favorites, cookies, site data, permissions and history are deleted. This can't be undone."
            )
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.send(.library(.createProfile(name: name)))
        newName = ""
    }
}

private struct ProfileRow: View {
    let model: AppModel
    let profile: Profile
    let delete: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit { model.send(.library(.renameProfile(profile.id, name: name))) }
                    .accessibilityLabel("Profile name")
                Spacer()
                let spaces = model.spaceCount(for: profile.id)
                Text("\(spaces) Space\(spaces == 1 ? "" : "s")").foregroundStyle(.secondary)
                if model.state.profiles.count > 1 {
                    Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete profile")
                        .accessibilityLabel("Delete profile \(profile.name)")
                }
            }
            if model.selectableEngines.count > 1 {
                Picker(
                    "Engine",
                    selection: Binding(
                        get: { profile.engine ?? model.selectableEngines.first?.id ?? .webKit },
                        set: { model.send(.library(.setEngine(profileID: profile.id, engine: $0))) })
                ) {
                    ForEach(model.selectableEngines, id: \.id) { engine in Text(engine.name).tag(engine.id) }
                }
                .accessibilityIdentifier("profiles.engine")
            }
        }
        .padding(.vertical, 4)
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, new in name = new }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profiles.row")
    }
}
