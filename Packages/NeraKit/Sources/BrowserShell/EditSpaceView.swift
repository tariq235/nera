// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

/// New Space and Edit Space: name, icon, colors, grain, light/dark and profile, with a live preview card.
/// Changes apply as you make them, so the window behind previews them too.
struct EditSpaceView: View {
    @Bindable var model: AppModel
    let spaceID: UUID
    @State private var name = ""
    @State private var emoji = ""
    @State private var showsSymbols = false
    @FocusState private var isNameFocused: Bool

    static let emojis = [
        "🌱", "💼", "🏠", "🎨", "✏️", "📚", "🎮", "🎵", "🛒", "✈️", "💡", "🔥", "🌊", "🍕", "🐳", "🧑‍💻",
        "📈", "🧠", "❤️", "⭐️", "🌙", "☕️", "🏃", "📷", "🎬", "🧩", "🪴", "⛰️", "🛠️", "💰", "📝", "🎯",
    ]
    static let symbols = [
        "house.fill", "briefcase.fill", "book.fill", "graduationcap.fill", "leaf.fill", "heart.fill", "star.fill", "sparkles",
        "moon.fill", "sun.max.fill", "flame.fill", "bolt.fill", "paintpalette.fill", "music.note", "gamecontroller.fill",
        "airplane", "cart.fill", "chart.bar.fill", "hammer.fill", "globe.americas.fill", "camera.fill", "film.fill",
        "cup.and.saucer.fill", "dumbbell.fill", "brain.head.profile", "terminal.fill", "dollarsign.circle.fill", "mountain.2.fill",
        "pawprint.fill", "fork.knife", "stethoscope", "building.2.fill",
    ]

    private var space: Space? { model.state.spaces.first { $0.id == spaceID } }

    var body: some View {
        if let space {
            VStack(spacing: 18) {
                Text(model.isCreatingSpace ? "New Space" : "Edit Space").font(.headline)
                HStack(alignment: .top, spacing: 20) {
                    SpacePreviewCard(space: space, name: name)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($isNameFocused)
                            .onSubmit { done() }
                            .accessibilityIdentifier("editSpace.name")
                        Picker("Icon kind", selection: $showsSymbols) {
                            Text("Emoji").tag(false)
                            Text("Symbols").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        iconGrid(space)
                        HStack(spacing: 8) {
                            Text("Custom emoji").font(.callout).foregroundStyle(.secondary)
                            TextField("😀", text: $emoji).frame(width: 52).textFieldStyle(.roundedBorder)
                                .onChange(of: emoji) { _, value in setEmoji(value) }
                        }
                    }
                    .frame(width: 360)
                }
                Divider()
                SpaceColorControls(theme: themeBinding(space))
                if model.state.profiles.count > 1 { profilePicker(space) }
                HStack {
                    Button("Cancel") { model.endEditingSpace(keep: false) }
                        .keyboardShortcut(.cancelAction)
                        .opacity(model.isCreatingSpace ? 1 : 0)
                        .disabled(!model.isCreatingSpace)
                    Spacer()
                    Button(model.isCreatingSpace ? "Create Space" : "Done") { done() }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("editSpace.done")
                }
            }
            .padding(24)
            .frame(width: 640)
            .onAppear {
                name = space.title
                if case .symbol = space.icon { showsSymbols = true }
                isNameFocused = true
            }
        }
    }

    private func done() {
        model.send(.space(.rename(spaceID, title: name)))
        model.endEditingSpace(keep: true)
    }

    private func iconGrid(_ space: Space) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 8), spacing: 6) {
            if showsSymbols {
                ForEach(Self.symbols, id: \.self) { symbol in
                    iconButton(.symbol(symbol), current: space.icon) { Image(systemName: symbol).font(.system(size: 15)) }
                }
            } else {
                ForEach(Self.emojis, id: \.self) { e in
                    iconButton(.emoji(e), current: space.icon) { Text(e).font(.system(size: 20)) }
                }
            }
        }
    }

    private func iconButton(_ icon: SpaceIcon, current: SpaceIcon, label: () -> some View) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                model.send(.space(.customize(spaceID, icon: icon, theme: nil)))
            }
        } label: {
            label()
                .frame(width: 38, height: 34)
                .background(
                    current == icon ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel({ if case .symbol(let s) = icon { s } else if case .emoji(let e) = icon { e } else { "" } }())
        .accessibilityAddTraits(current == icon ? [.isButton, .isSelected] : .isButton)
    }

    private func setEmoji(_ value: String) {
        guard let first = value.first, first.unicodeScalars.contains(where: \.properties.isEmojiPresentation) else { return }
        model.send(.space(.customize(spaceID, icon: .emoji(String(first)), theme: nil)))
    }

    private func profilePicker(_ space: Space) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(
                "Profile",
                selection: Binding(get: { space.profileID }, set: { model.send(.space(.setProfile(spaceID, profileID: $0))) })
            ) {
                ForEach(model.state.profiles) { Text($0.name).tag($0.id) }
            }
            .frame(width: 280)
            Text("Profiles keep Spaces truly separate: their own logins, cookies and site data. Spaces with the same profile share them.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func themeBinding(_ space: Space) -> Binding<SpaceTheme> {
        Binding(
            get: { space.theme },
            set: { edited in
                // Moving a color control on a Space imported with exact colors (Arc) makes it Nera's own from then on;
                // the appearance alone keeps them.
                var theme = edited
                let old = space.theme
                if theme.hue != old.hue || theme.saturation != old.saturation || theme.secondaryHue != old.secondaryHue
                    || theme.grain != old.grain
                {
                    theme.exact = nil
                }
                model.send(.space(.customize(spaceID, icon: nil, theme: theme)))
            })
    }
}

/// The live preview of a Space: its backdrop, icon and name over a sketch of a sidebar.
struct SpacePreviewCard: View {
    let space: Space
    let name: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Group {
                switch space.icon {
                case .emoji(let e): Text(e).font(.system(size: 46))
                case .symbol(let s): Image(systemName: s).font(.system(size: 38, weight: .medium))
                }
            }
            .id(space.icon)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            Text(name.isEmpty ? "Space" : name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            VStack(spacing: 8) {
                ForEach([0.75, 0.6], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.12)).frame(width: 170 * w, height: 26)
                }
            }
            Spacer()
        }
        .frame(width: 210, height: 250)
        .background(SpaceBackground(theme: space.theme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .environment(\.colorScheme, previewScheme)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: space.theme)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: space.icon)
        .accessibilityHidden(true)
    }

    @Environment(\.colorScheme) private var scheme
    private var previewScheme: ColorScheme {
        switch space.theme.appearance {
        case .dark: .dark
        case .light: .light
        case .system: scheme
        }
    }
}

/// Swatches, two hue sliders (color and blend), intensity, grain and appearance.
struct SpaceColorControls: View {
    @Binding var theme: SpaceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                ForEach(Array(SpaceTheme.swatches.enumerated()), id: \.offset) { _, swatch in
                    let isOn = theme.looksLike(swatch)
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { theme = swatch }
                    } label: {
                        LinearGradient(
                            colors: SpaceBackground.colors(swatch, dark: swatch.appearance == .dark), startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(isOn ? 0.85 : 0.12), lineWidth: isOn ? 2.5 : 1).padding(isOn ? -3 : 0)
                        )
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Color \(Int(swatch.hue * 360)) degrees")
                }
            }
            labeled("Color") { HueSlider(value: $theme.hue).accessibilityLabel("Color") }
            labeled("Blend") {
                HueSlider(value: Binding(get: { theme.secondaryHue ?? theme.hue }, set: { theme.secondaryHue = $0 })).accessibilityLabel(
                    "Blend color")
            }
            labeled("Intensity") { Slider(value: $theme.saturation, in: 0...0.9).accessibilityLabel("Intensity") }
            labeled("Grain") {
                Slider(value: Binding(get: { theme.grain ?? 0 }, set: { theme.grain = $0 }), in: 0...1).accessibilityLabel("Grain")
            }
            labeled("Appearance") {
                Picker("Appearance", selection: $theme.appearance) {
                    Text("Auto").tag(SpaceTheme.Appearance.system)
                    Text("Light").tag(SpaceTheme.Appearance.light)
                    Text("Dark").tag(SpaceTheme.Appearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 14) {
            Text(title).frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// A slider over the color wheel's hues.
struct HueSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: stride(from: 0.0, through: 1.0, by: 1 / 12).map { Color(hue: $0, saturation: 0.65, brightness: 0.9) },
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 10)
                Circle()
                    .fill(Color(hue: value, saturation: 0.65, brightness: 0.9))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: 22, height: 22)
                    .offset(x: max(0, min(width - 22, value * (width - 22))))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in value = min(max((g.location.x - 11) / max(width - 22, 1), 0), 1) })
        }
        .frame(height: 24)
        .accessibilityValue("\(Int(value * 360)) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 1 / 36)
            case .decrement: value = max(0, value - 1 / 36)
            @unknown default: break
            }
        }
    }
}
