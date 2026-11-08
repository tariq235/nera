// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

// The welcome screen's last steps: what was imported, and picking a look.

struct SummaryStep: View {
    let flow: OnboardingFlow
    let nera: Namespace.ID
    @Environment(\.welcomeMetrics) private var metrics
    @State private var isMovingPasswords = false

    var body: some View {
        let name = flow.source?.shortName ?? "your browser"
        StepColumn(
            title: flow.summary == nil ? "Bringing everything over…" : "Everything is here",
            detail: flow.summary == nil ? "This only takes a moment." : "Your \(name) life, now in Nera.", width: 620
        ) {
            NeraHalo(size: metrics.hero * 0.62, burst: flow.summary != nil).matchedGeometryEffect(id: "nera", in: nera)
        } controls: {
            VStack(spacing: 14) {
                if let summary = flow.summary {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(Array(StatTile.tiles(summary).enumerated()), id: \.offset) { i, tile in tile.reveal(i) }
                    }
                    if !summary.problems.isEmpty {
                        Text(
                            summary.problems == ["Sign-ins"]
                                ? "Sign-ins weren't brought over because access wasn't allowed. You can try again from Settings › Advanced."
                                : "\(summary.problems.joined(separator: " and ")) couldn't be read. Give Nera Full Disk Access in System Settings, then import again from Settings."
                        )
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    #if os(macOS)
                        if let source = flow.source, flow.hasSavedPasswords {
                            WelcomeGroup {
                                HStack(spacing: 12) {
                                    RowIcon(symbol: "key.fill", tint: .blue)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Bring your passwords").font(.system(size: 13.5, weight: .medium))
                                        Text("Move \(source.shortName)'s saved passwords to Apple Passwords; Nera fills them.")
                                            .font(.system(size: 12)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 12)
                                    Button("Move…") { isMovingPasswords = true }
                                        .accessibilityIdentifier("welcome.passwords")
                                }
                                .padding(.horizontal, 14).padding(.vertical, 11)
                            }
                            .frame(maxWidth: 520)
                            .sheet(isPresented: $isMovingPasswords, onDismiss: flow.setUpPasswordFilling) {
                                MovePasswordsView(model: flow.model, source: source)
                            }
                        }
                    #endif
                    if flow.needsRelaunch {
                        Label("Nera restarts once at the end to start your extensions.", systemImage: "arrow.clockwise")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A count that rolls up from zero, with what it counts under it.
struct StatTile: View {
    let symbol: String
    let value: Int
    let label: String
    @State private var shown = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Spectrum.ring)
            Text(shown.formatted())
                .font(.system(size: metrics.isCompact ? 21 : 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shown)))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: metrics.isTight ? 66 : metrics.isCompact ? 78 : 92)
        .background(palette.group, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.groupStroke))
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.25)) { shown = value }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    static func tiles(_ s: ImportSummary) -> [StatTile] {
        var tiles: [StatTile] = []
        func add(_ symbol: String, _ value: Int, _ label: String) {
            if value > 0 { tiles.append(StatTile(symbol: symbol, value: value, label: label)) }
        }
        add("square.stack.3d.up.fill", s.spaces, s.spaces == 1 ? "Space" : "Spaces")
        add("pin.fill", s.tabs, s.tabs == 1 ? "Tab" : "Tabs")
        add("folder.fill", s.folders, s.folders == 1 ? "Folder" : "Folders")
        add("star.fill", s.favorites, s.favorites == 1 ? "Favorite" : "Favorites")
        add("archivebox.fill", s.archived, "Archived")
        add("book.fill", s.bookmarks, s.bookmarks == 1 ? "Bookmark" : "Bookmarks")
        add("clock.fill", s.history, "History pages")
        add("app.badge.fill", s.icons, "Site icons")
        add("key.fill", s.signIns, s.signIns == 1 ? "Signed-in site" : "Signed-in sites")
        if tiles.isEmpty { tiles.append(StatTile(symbol: "checkmark.seal.fill", value: 0, label: "Nothing else to bring")) }
        return tiles
    }
}

struct ThemeStep: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepWithPreview(title: "Make it yours", detail: "Pick a color for your Spaces. Each Space can have its own, any time.") {
            VStack(alignment: .leading, spacing: 22) {
                ThemeSwatches(selection: $flow.theme).reveal(3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    PillPicker(options: [("Auto", .system), ("Light", .light), ("Dark", .dark)], selection: $flow.theme.appearance)
                        .accessibilityLabel("Appearance")
                }
                .reveal(4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grain").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    NeraSlider(value: Binding(get: { flow.theme.grain ?? 0 }, set: { flow.theme.grain = $0 }))
                        .frame(width: 252)
                        .accessibilityLabel("Grain")
                }
                .reveal(5)
            }
        } preview: {
            let model = flow.model
            let space = model.state.selectedSpace ?? model.state.spaces.first
            FittedPreview {
                MiniBrowser(
                    theme: flow.theme, favorites: (model.state.currentProfile?.favorites ?? []).compactMap(\.url),
                    spaceTitle: space?.title ?? "",
                    spaceIcon: space?.icon, pinned: (space?.pinned ?? []).flatMap(\.tabs), today: (space?.today ?? []).flatMap(\.tabs),
                    placeholderRows: (space.map { ($0.pinned + $0.today).isEmpty } ?? true) ? 5 : 0,
                    icon: { $0.flatMap(model.favicon(forURL:)) })
            }
        }
    }
}

/// The ready-made looks as gradient dots; the picked one gets a ring and a check.
struct ThemeSwatches: View {
    @Binding var selection: SpaceTheme
    var size: CGFloat = 34

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 12), count: 6), alignment: .leading, spacing: 12) {
            ForEach(Array(SpaceTheme.swatches.enumerated()), id: \.offset) { _, swatch in
                let isOn = selection.looksLike(swatch)
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { selection = swatch }
                } label: {
                    LinearGradient(
                        colors: SpaceBackground.colors(swatch, dark: swatch.appearance == .dark), startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.35)))
                    .overlay {
                        Image(systemName: "checkmark").font(.system(size: size * 0.34, weight: .bold))
                            .foregroundStyle(swatch.appearance == .dark ? .white : .black.opacity(0.75))
                            .scaleEffect(isOn ? 1 : 0.3).opacity(isOn ? 1 : 0)
                    }
                    .frame(width: size, height: size)
                    .padding(3)
                    .overlay(Circle().strokeBorder(.primary.opacity(isOn ? 0.6 : 0), lineWidth: 2))
                    .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Color \(Int(swatch.hue * 360)) degrees, \(swatch.appearance == .dark ? "dark" : "light")")
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
