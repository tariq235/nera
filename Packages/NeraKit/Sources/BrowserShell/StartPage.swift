// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import SwiftUI

/// Shown when no tab is selected: a greeting, a search box, your most visited sites and a few tips.
/// Everything here is local: nothing is fetched to draw it.
struct StartPage: View {
    let model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    private var theme: SpaceTheme? { model.state.selectedSpace?.theme }

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)
                    greeting
                    searchBox
                    sites
                    tips
                    privacyLine
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .accessibilityIdentifier("startPage")
    }

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(
                colors: [Theme.accent(for: theme).opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                startPoint: .top, endPoint: .center)
            RadialGradient(
                colors: [Theme.accent(for: theme).opacity(scheme == .dark ? 0.18 : 0.10), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
    }

    private var greeting: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 6) {
                Text(Self.greeting(for: context.date))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title3)
                    // 70% of the primary color: 5.6:1 on the start page (WCAG AA needs 4.5:1); `.secondary` was 4.0:1.
                    .foregroundStyle(.primary.opacity(0.7))
                    .accessibilityIdentifier("start.date")
            }
        }
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
    }

    private var searchBox: some View {
        Button {
            model.showCommandBar(.newTab)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Search \(model.state.settings.searchEngine.name) or enter an address")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Spacer()
                KeyCap("⌘T")
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08), radius: 14, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("empty.newTab")
    }

    /// Most visited sites, or the profile's Favorites while there's no history yet.
    private var siteEntries: [(url: URL, title: String)] {
        let top = model.topSites
        if !top.isEmpty { return top }
        return (model.state.currentProfile?.favorites ?? []).compactMap { tab in tab.url.map { ($0, tab.displayTitle) } }
    }

    @ViewBuilder private var sites: some View {
        let entries = Array(siteEntries.prefix(8))
        if !entries.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(entries, id: \.url) { entry in
                    SiteTile(url: entry.url, title: entry.title, icon: model.favicon(forURL: entry.url)) {
                        model.send(.tab(.open(entry.url, .newTab)))
                    }
                }
            }
        }
    }

    private var tips: some View {
        HStack(spacing: 12) {
            TipCard(symbol: "rectangle.split.2x1", title: "Split View", detail: "Two pages side by side", keys: "⌃⌘N") {
                model.showCommandBar(model.state.selectedTab == nil ? .newTab : .splitWithCurrent)
            }
            TipCard(symbol: "square.stack.3d.up", title: "Spaces", detail: "Separate work and life", keys: "⌃1–9") {
                if let id = model.state.selectedSpace?.id { model.editSpace(id) }
            }
            TipCard(symbol: "eyeglasses", title: "Private window", detail: "Nothing kept after closing", keys: "⇧⌘N") {
                openWindow(id: AppModel.privateWindowID)
            }
            .disabled(model.isPrivate)
        }
    }

    private var privacyLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Theme.accent(for: theme)).accessibilityHidden(true)  // the text says it
            Text(
                model.state.settings.httpsOnly
                    ? "HTTPS-Only is on · no telemetry · your data stays on this Mac" : "No telemetry · your data stays on this Mac")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// A most-visited site: big icon and its name.
struct SiteTile: View {
    let url: URL
    let title: String
    let icon: Data?
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SiteIcon(url: url, size: 26, png: icon)
                    .frame(width: 52, height: 52)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: isHovering ? 8 : 4, y: 2)
                Text(Self.name(url: url, title: title))
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isHovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(isHovering ? 1.03 : 1)
            .animation(.snappy(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(url.absoluteString)
    }

    /// The site's name: "GitHub" from "GitHub: Let's build from here" on github.com; otherwise from the host
    /// ("stackoverflow.com" → "Stackoverflow"), so page titles like "Sign in" never label a site.
    static func name(url: URL, title: String) -> String {
        let host = (url.host() ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let parts = host.split(separator: ".").map(String.init)
        let label = parts.count >= 2 ? parts[parts.count - 2] : host  // open.spotify.com → spotify
        let short = title.split(whereSeparator: { ":|–-·".contains($0) }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !short.isEmpty, short.count <= 18, short.lowercased().replacingOccurrences(of: " ", with: "").contains(label) { return short }
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

/// One of the start page's feature tips.
struct TipCard: View {
    let symbol: String
    let title: String
    let detail: String
    let keys: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(.tint)
                    Spacer()
                    KeyCap(keys)
                }
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(isHovering ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A keyboard shortcut drawn as a key.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.1)))
    }
}
