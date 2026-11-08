// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import Import
import SwiftUI

// The welcome screen's steps. Each is a centered column: an illustration, a headline, a line of detail and its
// controls, entering in a short stagger. Steps with a live preview put it beside the controls in wide windows.

/// A step's headline and detail.
struct StepHeading: View {
    let title: String
    var detail: String?
    var alignment: HorizontalAlignment = .center
    @Environment(\.welcomeMetrics) private var metrics
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text: TextAlignment = alignment == .center ? .center : .leading
        VStack(alignment: alignment, spacing: 10) {
            Text(title)
                .font(metrics.title)
                .tracking(-0.7)
                .multilineTextAlignment(text)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(1)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.system(size: metrics.isCompact ? 14.5 : 16))
                    .foregroundStyle(WelcomePalette(scheme: scheme).secondary)
                    .multilineTextAlignment(text)
                    .lineSpacing(2)
                    .frame(maxWidth: 520, alignment: alignment == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(2)
            }
        }
    }
}

/// The usual step: illustration, heading, then controls, centered as a column.
struct StepColumn<Hero: View, Controls: View>: View {
    let title: String
    var detail: String?
    var width: CGFloat = 520
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var controls: () -> Controls
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.gap) {
            Spacer(minLength: 0)
            hero().frame(height: metrics.hero).reveal(0)
            StepHeading(title: title, detail: detail)
            controls().frame(maxWidth: width)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A step with a live preview: controls on the left and the preview on the right in wide windows; the
/// preview is left out when the window is narrow.
struct StepWithPreview<Controls: View, Preview: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var preview: () -> Preview
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        if metrics.isWide {
            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: metrics.gap) {
                    StepHeading(title: title, detail: detail, alignment: .leading)
                    controls()
                }
                .frame(width: 440)
                preview()
                    .frame(maxWidth: 560, maxHeight: min(metrics.size.height - 220, 520))
                    .reveal(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: metrics.gap) {
                StepHeading(title: title, detail: detail)
                controls().frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct IntroStep: View {
    let nera: Namespace.ID
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        StepColumn(
            title: "A browser that feels like light",
            detail: "Spaces for every part of your life, a sidebar that keeps itself tidy, split view and a command bar "
                + "that learns. No account, no telemetry. Everything stays on your Mac."
        ) {
            NeraHalo(size: metrics.hero * 0.66, burst: true).matchedGeometryEffect(id: "nera", in: nera)
        } controls: {
            EmptyView()
        }
    }
}

struct EssentialsStep: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        StepColumn(
            title: "Make yourself at home", detail: "Three small things that make Nera part of your Mac. Change them any time in Settings."
        ) {
            DockScene(
                height: metrics.hero, isInDock: flow.addToDock || flow.isAlreadyInDock,
                isDefault: flow.makeDefault || flow.isAlreadyDefault,
                neighbors: dockNeighbors)
        } controls: {
            WelcomeGroup {
                ToggleRow(
                    title: "Default browser",
                    detail: flow.isAlreadyDefault
                        ? "Nera already opens your links" : "Links from Mail, Messages and other apps open in Nera",
                    isOn: $flow.makeDefault, isLocked: flow.isAlreadyDefault
                ) { RowIcon(symbol: "link", tint: .blue) }
                ToggleRow(
                    title: "Keep in the Dock",
                    detail: flow.isAlreadyInDock ? "Nera is already in your Dock" : "One click away, next to your other apps",
                    isOn: $flow.addToDock, isLocked: flow.isAlreadyInDock
                ) { RowIcon(symbol: "dock.rectangle", tint: .indigo) }
                ToggleRow(title: "Open at login", detail: "Ready the moment you sign in", isOn: $flow.openAtLogin, showsDivider: false) {
                    RowIcon(symbol: "power", tint: .green)
                }
            }
            .reveal(3)
        }
    }

    private var dockNeighbors: [Image] {
        #if os(macOS)
            ["com.apple.finder", "com.apple.mail", "com.apple.MobileSMS"].compactMap(Image.app)
        #else
            []
        #endif
    }
}

struct PrivacyStep: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        StepColumn(
            title: "Private by design",
            detail: "Nera has no account and sends nothing about you anywhere. Your Spaces, tabs and history are files on your Mac."
        ) {
            ShieldScene(size: metrics.hero, isBlocking: flow.blockTrackers)
                .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: metrics.hero * 1.05))
        } controls: {
            VStack(spacing: 16) {
                if flow.model.supportsExtensions {
                    WelcomeGroup {
                        ToggleRow(
                            title: "Block ads and trackers", detail: "Uses uBlock Origin Lite, on every site", isOn: $flow.blockTrackers,
                            showsDivider: false
                        ) { RowIcon(symbol: "hand.raised.fill", tint: .orange) }
                        .accessibilityIdentifier("welcome.blockTrackers")
                    }
                }
                HStack(spacing: 8) {
                    FactChip(symbol: "lock.fill", text: "HTTPS first")
                    FactChip(symbol: "eye.slash.fill", text: "No telemetry")
                    FactChip(symbol: "internaldrive.fill", text: "Your data stays on this Mac")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Always on: HTTPS first, no telemetry, your data stays on this Mac")
            }
            .reveal(3)
        }
    }
}

/// Something that is always true in Nera (not a setting): an icon and a few words on a glass capsule.
struct FactChip: View {
    let symbol: String
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Spectrum.ring)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 11).frame(height: 28)
        .background(palette.group, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.groupStroke))
    }
}

struct SourceStep: View {
    @Bindable var flow: OnboardingFlow
    let nera: Namespace.ID
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        StepColumn(
            title: "Bring your browser with you",
            detail: "Spaces, tabs, folders, archive, history, sign-ins and extensions. Nothing leaves your Mac.", width: 620
        ) {
            ImportBeam(height: metrics.hero, source: flow.source?.appIcon)
        } controls: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ForEach(Array(flow.sources.enumerated()), id: \.element) { i, source in
                        BrowserChoice(name: source.shortName, icon: source.appIcon, isSelected: flow.source == source) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                flow.source = flow.source == source ? nil : source
                            }
                        }
                        .reveal(3 + i)
                        .accessibilityIdentifier("welcome.source.\(source.rawValue)")
                    }
                }
                if let source = flow.source, source.isChromium {
                    WelcomeGroup {
                        ToggleRow(
                            title: "Stay signed in to websites",
                            detail: "Brings your \(source.shortName) sign-ins over. macOS asks once: choose Always Allow.",
                            isOn: $flow.includeSignIns, showsDivider: false
                        ) { RowIcon(symbol: "key.fill", tint: .green) }
                        .accessibilityIdentifier("welcome.signIns")
                    }
                    .frame(maxWidth: 460)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }
}

/// A browser to import from: its icon on a glass tile, its name under it. The picked one lifts and glows.
struct BrowserChoice: View {
    let name: String
    let icon: Image?
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        Button(action: action) {
            VStack(spacing: 10) {
                Group {
                    if let icon {
                        icon.resizable().interpolation(.high).scaledToFit()
                    } else {
                        Image(systemName: "globe").font(.largeTitle)
                    }
                }
                .frame(width: 54, height: 54)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.ink).lineLimit(1).fixedSize()
            }
            .frame(width: 108, height: 112)
            .background(palette.group, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Spectrum.ring) : AnyShapeStyle(palette.groupStroke), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(7)
                    .scaleEffect(isSelected ? 1 : 0.3)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(isSelected ? 1.04 : (isHovering ? 1.02 : 1))
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 14 : 6, y: isSelected ? 8 : 3)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SpacesStep: View {
    @Bindable var flow: OnboardingFlow
    @State private var previewID: UUID?
    @Environment(\.welcomeMetrics) private var metrics

    private var spaces: [Space] { flow.arcPreview?.library.spaces ?? [] }

    var body: some View {
        let name = flow.source?.shortName ?? "your browser"
        StepWithPreview(title: "Choose what comes over", detail: "Pick the Spaces to bring from \(name). Hover one to see it.") {
            ScrollView {
                VStack(spacing: 14) {
                    WelcomeGroup {
                        ForEach(Array(spaces.enumerated()), id: \.element.id) { i, space in
                            ToggleRow(title: space.title, detail: count(space), isOn: binding(space.id), showsDivider: i < spaces.count - 1)
                            {
                                RowIcon(symbol: symbol(space.icon), tint: .accentColor, emoji: emoji(space.icon))
                            }
                            .onHover { if $0 { previewID = space.id } }
                        }
                    }
                    WelcomeGroup {
                        if let archive = flow.arcPreview?.archive, !archive.isEmpty {
                            ToggleRow(
                                title: "Archived tabs", detail: "\(archive.count.formatted()) tabs you closed", isOn: $flow.includeArchive
                            ) {
                                RowIcon(symbol: "archivebox.fill", tint: .brown)
                            }
                        }
                        ToggleRow(
                            title: "Bookmarks and history", detail: "So the command bar knows your sites", isOn: $flow.includeHistory,
                            showsDivider: false
                        ) { RowIcon(symbol: "clock.arrow.circlepath", tint: .blue) }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: metrics.size.height - (metrics.isWide ? 300 : 292))
            .fixedSize(horizontal: false, vertical: true)
            .mask(ScrollFade())
            .reveal(3)
        } preview: {
            let space = spaces.first { $0.id == previewID } ?? spaces.first { flow.pickedSpaces.contains($0.id) }
            FittedPreview {
                MiniBrowser(
                    theme: SpaceTheme.swatches[10], favorites: (flow.arcPreview?.library.favorites ?? []).compactMap(\.url),
                    spaceTitle: space?.title ?? "", spaceIcon: space?.icon, pinned: (space?.pinned ?? []).flatMap(\.tabs),
                    today: (space?.today ?? []).flatMap(\.tabs), icon: icon)
            }
        }
    }

    private var icon: (URL?) -> Data? { { [model = flow.model] in $0.flatMap(model.favicon(forURL:)) } }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { flow.pickedSpaces.contains(id) },
            set: { on in
                if on { flow.pickedSpaces.insert(id) } else { flow.pickedSpaces.remove(id) }
                previewID = id
            })
    }

    private func count(_ space: Space) -> String {
        let n = (space.pinned + space.today).flatMap(\.tabs).count
        return n == 1 ? "1 tab" : "\(n) tabs"
    }

    private func emoji(_ icon: SpaceIcon) -> String? { if case .emoji(let e) = icon { e } else { nil } }
    private func symbol(_ icon: SpaceIcon) -> String? { if case .symbol(let s) = icon { s } else { nil } }
}

struct ExtensionsStep: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.welcomeMetrics) private var metrics

    var body: some View {
        StepColumn(title: "Your extensions, freshly installed", detail: "Nera gets the latest version of each from the Chrome Web Store.") {
            ExtensionShelf(icons: picked.map { $0.icon.flatMap(SiteIcon.image) ?? Image(systemName: "puzzlepiece.extension.fill") })
        } controls: {
            ScrollView {
                WelcomeGroup {
                    ForEach(Array(flow.foundExtensions.enumerated()), id: \.element.id) { i, ext in
                        ToggleRow(
                            title: ext.name, detail: detail(ext), isOn: ext.isSupported ? binding(ext.id) : .constant(false),
                            isLocked: !ext.isSupported,
                            showsDivider: i < flow.foundExtensions.count - 1, lockedText: "Not available", lockedSymbol: "minus.circle"
                        ) { RowIcon(symbol: "puzzlepiece.extension.fill", tint: .gray, image: ext.icon.flatMap(SiteIcon.image)) }
                        .opacity(ext.isSupported ? 1 : 0.55)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: max(170, metrics.size.height - metrics.hero - 330))
            .fixedSize(horizontal: false, vertical: true)
            .mask(ScrollFade())
            .reveal(3)
        }
    }

    private var picked: [FoundExtension] { flow.foundExtensions.filter { flow.pickedExtensions.contains($0.id) } }

    private func detail(_ ext: FoundExtension) -> String {
        let source = flow.source?.shortName ?? "your browser"
        if !ext.isSupported { return "Built for Manifest V2, which Chromium no longer runs" }
        return ext.wasEnabled ? "On in \(source)" : "Off in \(source)"
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { flow.pickedExtensions.contains(id) },
            set: { if $0 { flow.pickedExtensions.insert(id) } else { flow.pickedExtensions.remove(id) } })
    }
}

/// Picked extensions popping onto a toolbar.
struct ExtensionShelf: View {
    let icons: [Image]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(icons.prefix(6).enumerated()), id: \.offset) { _, image in
                image.resizable().interpolation(.high).scaledToFit().frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            Image(systemName: "puzzlepiece.extension").font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.4)))
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: icons.count)
    }
}

/// Fades the last few points of a scrolling list, so a cut-off row reads as "more below".
struct ScrollFade: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
        }
    }
}

struct FavoritesStep: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.colorScheme) private var scheme
    @State private var iconsLoaded = 0

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        StepWithPreview(title: "Pick a few Favorites", detail: "They sit at the top of the sidebar in every Space, one click away.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Array(WelcomeSuggestions.sites.enumerated()), id: \.element.url) { i, site in
                    let isOn = flow.pickedFavorites.contains(site.url)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            if isOn { flow.pickedFavorites.remove(site.url) } else { flow.pickedFavorites.insert(site.url) }
                        }
                    } label: {
                        VStack(spacing: 7) {
                            SiteIcon(url: site.url, size: 22, png: flow.model.favicon(forURL: site.url)).id(iconsLoaded)
                            Text(site.name).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(palette.group, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isOn ? AnyShapeStyle(Spectrum.ring) : AnyShapeStyle(palette.groupStroke), lineWidth: isOn ? 2 : 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(site.name)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .reveal(3 + i / 4)
                }
            }
        } preview: {
            FittedPreview {
                MiniBrowser(
                    theme: SpaceTheme.swatches[10], favorites: WelcomeSuggestions.sites.map(\.url).filter(flow.pickedFavorites.contains),
                    spaceTitle: flow.model.state.selectedSpace?.title ?? "", spaceIcon: flow.model.state.selectedSpace?.icon,
                    placeholderRows: 5, icon: { [model = flow.model] in $0.flatMap(model.favicon(forURL:)) }
                )
                .id(iconsLoaded)
            }
        }
        .task {
            #if os(macOS)
                iconsLoaded = flow.model.borrowIconsFromInstalledBrowsers()
            #endif
        }
    }
}
