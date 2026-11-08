// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import SwiftUI

/// ⌘F: find in the current page.
struct FindBar: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: $model.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($focused)
                .onSubmit { Task { await model.find() } }
                .accessibilityIdentifier("find.field")
            Text(status).font(.caption).foregroundStyle(model.findResult?.matchFound == false ? .red : .secondary)
                .monospacedDigit()
                .accessibilityIdentifier("find.status")
            Button {
                Task { await model.find(backwards: true) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous (⇧⌘G)")
            .accessibilityLabel("Previous match")
            Button {
                Task { await model.find() }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next (⌘G)")
            .accessibilityLabel("Next match")
            Button("Done") { model.hideFindBar() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: model.findQuery) { _, _ in Task { await model.find() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find.bar")
    }

    private var status: String {
        guard let result = model.findResult, !model.findQuery.isEmpty else { return "" }
        guard result.matchFound else { return "No matches" }
        if let count = result.matchCount, let active = result.activeMatch { return "\(active) of \(count)" }
        if let count = result.matchCount { return "\(count) matches" }
        return ""
    }
}

/// The brief "125%" after zooming.
struct ZoomIndicator: View {
    let factor: Double

    var body: some View {
        Text("\(Int((factor * 100).rounded()))%")
            .font(.title3.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
            .accessibilityLabel("Zoom \(Int((factor * 100).rounded())) percent")
            .accessibilityIdentifier("zoom.indicator")
    }
}
