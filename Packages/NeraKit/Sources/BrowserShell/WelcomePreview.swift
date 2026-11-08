// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Shows a ``MiniBrowser`` (drawn at its natural size) scaled to fit the space it's given, never cropped.
struct FittedPreview<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / MiniBrowser.size.width, geo.size.height / MiniBrowser.size.height, 1)
            content()
                .frame(width: MiniBrowser.size.width, height: MiniBrowser.size.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(MiniBrowser.size.width / MiniBrowser.size.height, contentMode: .fit)
    }
}

/// A small, live Nera window for the welcome screen: the user's own Favorites and tabs in the chosen look.
struct MiniBrowser: View {
    static let size = CGSize(width: 720, height: 520)

    let theme: SpaceTheme
    var favorites: [URL] = []
    var spaceTitle = ""
    var spaceIcon: SpaceIcon?
    var pinned: [BrowserCore.Tab] = []
    var today: [BrowserCore.Tab] = []
    var placeholderRows = 0
    let icon: (URL?) -> Data?

    private var scheme: ColorScheme {
        switch theme.appearance {
        case .dark: .dark
        case .light: .light
        case .system: SystemAppearance.isDark ? .dark : .light
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar.frame(width: 248)
            content
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(SpaceBackground(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.3)))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 16)
        .environment(\.colorScheme, scheme)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: theme)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: favorites)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pinned.map(\.id) + today.map(\.id))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                ForEach(
                    [
                        Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                        Color(red: 0.16, green: 0.79, blue: 0.25),
                    ], id: \.self
                ) {
                    Circle().fill($0).frame(width: 11, height: 11)
                }
                Image(systemName: "sidebar.left").padding(.leading, 8)
                Spacer()
                Image(systemName: "arrow.left")
                Image(systemName: "arrow.right").opacity(0.45)
                Image(systemName: "arrow.clockwise")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.55))
            .frame(height: 20)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .medium))
                Text("Search or enter address").font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.primary.opacity(0.5))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .surface(.resting, cornerRadius: 9)
            if !favorites.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(favorites.prefix(8), id: \.self) { url in
                        SiteIcon(url: url, size: 17, png: icon(url))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .surface(.resting, cornerRadius: 10)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            }
            if !spaceTitle.isEmpty {
                HStack(spacing: 6) {
                    if let spaceIcon { SpaceIconView(icon: spaceIcon) }
                    Text(spaceTitle).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary.opacity(0.6))
                .id(spaceTitle)
                .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pinned.prefix(5)) { row($0) }
                if !pinned.isEmpty, !today.isEmpty { Rectangle().fill(.primary.opacity(0.1)).frame(height: 1).padding(.vertical, 5) }
                ForEach(today.prefix(5)) { row($0) }
                ForEach(0..<placeholderRows, id: \.self) { i in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.13)).frame(width: 16, height: 16)
                        Capsule().fill(.primary.opacity(0.13)).frame(width: [92, 64, 108, 78, 58][i % 5], height: 8)
                    }
                    .frame(height: 30)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func row(_ tab: BrowserCore.Tab) -> some View {
        HStack(spacing: 9) {
            SiteIcon(url: tab.url, size: 14, png: icon(tab.url))
            Text(tab.displayTitle).font(.system(size: 12)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
        }
        .frame(height: 30)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var content: some View {
        VStack(spacing: 14) {
            Spacer()
            RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.07)).frame(width: 220, height: 30)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.05)).frame(width: 44, height: 44)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 8)
        .padding(.trailing, 8)
    }
}

/// Whether the system is in dark mode right now (for previews that follow it).
enum SystemAppearance {
    @MainActor static var isDark: Bool {
        #if os(macOS)
            NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
            false
        #endif
    }
}
