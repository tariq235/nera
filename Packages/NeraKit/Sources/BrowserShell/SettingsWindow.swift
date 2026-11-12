// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Import
public import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
    import BrowserData
#endif

/// The app's Settings window (⌘,): a sidebar of sections, like System Settings.
public struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var section: SettingsSection? = SettingsSection.initial

    /// Creates the settings content.
    public init(model: AppModel) { self.model = model }

    /// The window content.
    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.visible, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(190)
            #if os(macOS)
                .toolbar(removing: .sidebarToggle)
            #endif
        } detail: {
            detail.navigationTitle(section?.title ?? "")
        }
        #if os(macOS)
            .frame(width: 760, height: 560)
        #endif
    }

    @ViewBuilder private var detail: some View {
        switch section ?? .general {
        case .general: GeneralSettingsView(model: model)
        case .tabs: TabsSettingsView(model: model)
        case .links: LinksSettingsView(model: model)
        case .passwords:
            #if os(macOS)
                PasswordsSettingsView(model: model)
            #else
                EmptyView()
            #endif
        case .privacy: PrivacySettingsView(model: model)
        case .profiles: ProfilesSettingsView(model: model)
        case .sites: SiteSettingsView(model: model)
        case .extensions:
            #if os(macOS)
                ExtensionsSettingsView(model: model)
            #else
                EmptyView()
            #endif
        case .shortcuts: ShortcutsSettingsView()
        case .advanced: AdvancedSettingsView(model: model)
        }
    }
}

/// A section of the Settings window.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, tabs, links, passwords, privacy, profiles, sites, extensions, shortcuts, advanced

    var id: String { rawValue }

    /// The section shown first (Debug screenshots can pick one with `--shot settings-<section>`).
    static var initial: SettingsSection {
        #if DEBUG
            if let i = CommandLine.arguments.firstIndex(of: "--shot"), i + 1 < CommandLine.arguments.count,
                let s = SettingsSection(rawValue: String(CommandLine.arguments[i + 1].dropFirst("settings-".count)))
            {
                return s
            }
        #endif
        return .general
    }

    /// The sections this platform shows.
    static var visible: [SettingsSection] {
        #if os(macOS)
            allCases
        #else
            allCases.filter { $0 != .extensions && $0 != .passwords }
        #endif
    }

    var title: String {
        switch self {
        case .general: "General"
        case .tabs: "Tabs"
        case .links: "Links"
        case .passwords: "Passwords"
        case .privacy: "Privacy"
        case .profiles: "Profiles"
        case .sites: "Site Settings"
        case .extensions: "Extensions"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .links: "arrow.triangle.branch"
        case .passwords: "key"
        case .privacy: "hand.raised"
        case .profiles: "person.2"
        case .sites: "globe"
        case .extensions: "puzzlepiece.extension"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        }
    }
}

/// Settings › General: default browser, search engine, updates.
struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    #if os(macOS)
        @State private var isDefault = DefaultBrowser.isDefault
    #endif

    var body: some View {
        Form {
            #if os(macOS)
                Section("Default Browser") {
                    HStack {
                        Label(
                            isDefault ? "Nera is your default browser" : "Nera isn't your default browser",
                            systemImage: isDefault ? "checkmark.seal.fill" : "globe")
                        Spacer()
                        if !isDefault {
                            Button("Make Default") { DefaultBrowser.makeDefault { isDefault = $0 } }
                                .accessibilityIdentifier("general.makeDefault")
                        }
                    }
                }
            #endif
            Section {
                Picker(
                    "Appearance",
                    selection: Binding(get: { model.state.settings.appearance }, set: { model.send(.library(.setAppearance($0))) })
                ) {
                    Text("Match Mac").tag(AppearanceChoice.system)
                    Text("Light").tag(AppearanceChoice.light)
                    Text("Dark").tag(AppearanceChoice.dark)
                    Text("Each Space's choice").tag(AppearanceChoice.perSpace)
                }
                .accessibilityIdentifier("general.appearance")
            } header: {
                Text("Appearance")
            } footer: {
                Text("Match Mac follows System Settings › Appearance. Private windows are always dark.").foregroundStyle(.secondary)
            }
            Section {
                Picker("Search engine", selection: searchEngine) {
                    ForEach(choices, id: \.self) { Text($0.name).tag($0) }
                }
                .accessibilityIdentifier("general.searchEngine")
            } header: {
                Text("Address Bar")
            } footer: {
                Text("Used when what you type in the address bar isn't a web address.").foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Pop out videos when you switch tabs",
                    isOn: Binding(
                        get: { model.state.settings.autoPictureInPicture },
                        set: { model.send(.library(.setAutoPictureInPicture($0))) })
                )
                .accessibilityIdentifier("general.autoPictureInPicture")
            } header: {
                Text("Videos")
            } footer: {
                Text("A video playing with sound keeps playing in a floating window when you leave its tab, and goes back when you return.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Let assistive apps read web pages",
                    isOn: Binding(get: { model.letsAssistiveAppsReadPages }, set: { model.letsAssistiveAppsReadPages = $0 })
                )
                .accessibilityIdentifier("general.assistiveApps")
                #if os(macOS)
                    if model.assistiveSettingNeedsRestart {
                        HStack {
                            Text("Applies after Nera restarts.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Restart Nera") { model.relaunch() }.accessibilityIdentifier("general.assistiveRestart")
                        }
                    }
                #endif
            } header: {
                Text("Accessibility")
            } footer: {
                Text(
                    "For VoiceOver, Voice Control and Switch Control in Chromium pages (WebKit pages are always readable). Turned on for you when VoiceOver or Switch Control is used. Uses a little more memory."
                )
                .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle(
                    "Check for new versions automatically",
                    isOn: Binding(get: { model.checksForUpdates }, set: { model.checksForUpdates = $0 }))
                HStack {
                    Text(updateText).foregroundStyle(.secondary)
                    Spacer()
                    switch model.updateStatus {
                    case .ready:
                        #if os(macOS)
                            Button("Restart to Update") { model.restartToUpdate() }
                        #endif
                    case .preparing:
                        ProgressView().controlSize(.small)
                    case .idle:
                        Button("Check Now") { model.checkForUpdates(force: true) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
            .onAppear { isDefault = DefaultBrowser.isDefault }
        #endif
    }

    private var updateText: String {
        switch model.updateStatus {
        case .idle: "Nera \(model.appVersion) (\(model.appBuild))"
        case .preparing(let version): "Getting Nera \(version) ready…"
        case .ready(let version): "Nera \(version) is ready to install"
        }
    }

    /// The presets, plus the current engine if it's a custom one.
    private var choices: [SearchEngine] {
        let current = model.state.settings.searchEngine
        return SearchEngine.presets.contains(current) ? SearchEngine.presets : SearchEngine.presets + [current]
    }

    private var searchEngine: Binding<SearchEngine> {
        Binding(get: { model.state.settings.searchEngine }, set: { model.send(.library(.setSearchEngine($0))) })
    }
}

/// Settings › Tabs: when tabs are archived.
struct TabsSettingsView: View {
    @Bindable var model: AppModel
    static let archiveChoices: [(label: String, seconds: TimeInterval)] = [
        ("12 hours", 12 * 3600), ("24 hours", 24 * 3600), ("7 days", 7 * 86400), ("30 days", 30 * 86400),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Archive tabs after", selection: archiveAfter) {
                    ForEach(Self.archiveChoices, id: \.seconds) { Text($0.label).tag($0.seconds) }
                    if !Self.archiveChoices.contains(where: { $0.seconds == model.state.settings.archiveAfter }) {
                        Text(Duration.seconds(model.state.settings.archiveAfter).formatted(.units(allowed: [.days, .hours])))
                            .tag(model.state.settings.archiveAfter)
                    }
                }
                .accessibilityIdentifier("tabs.archiveAfter")
            } footer: {
                Text(
                    "Tabs you haven't opened for this long move to the archive (⌘Y finds them again). Pinned tabs and Favorites are never archived."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var archiveAfter: Binding<TimeInterval> {
        Binding(get: { model.state.settings.archiveAfter }, set: { model.send(.library(.setArchiveAfter($0))) })
    }
}

/// Settings › Privacy: what Nera always does, and clearing browsing data.
struct PrivacySettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Always On") {
                fact("lock.fill", "HTTPS first", "Pages load over a secure connection whenever the site supports it.")
                fact("chart.bar.xaxis", "No telemetry", "Nera never sends usage data, crash reports or your browsing anywhere.")
                fact("internaldrive", "On this Mac", "Your tabs, history and settings stay on this Mac.")
            }
            Section {
                Toggle(
                    "Warn about dangerous sites",
                    isOn: Binding(get: { model.warnsAboutDangerousSites }, set: { model.warnsAboutDangerousSites = $0 })
                )
                .disabled(!model.safeBrowsingAvailable)
                .accessibilityIdentifier("privacy.safeBrowsing")
            } footer: {
                Text(
                    model.safeBrowsingAvailable
                        ? "Google Safe Browsing lists are kept on this Mac. Only when a site's address matches one is a short fingerprint of it sent to Google, which also sees your IP address. Protection isn't perfect: some dangerous sites aren't flagged, and a safe site is occasionally flagged by mistake. WebKit pages use Apple's Fraudulent Website Warning."
                        : "Not available in this build."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear browsing data")
                        Text("History, cookies, site data and cache").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear…") { model.isClearDataPresented = true }
                        .disabled(model.isPrivate)
                        .accessibilityIdentifier("privacy.clear")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings › Shortcuts: the keyboard shortcuts, grouped.
struct ShortcutsSettingsView: View {
    static let groups: [(title: String, items: [(String, String)])] = [
        (
            "Tabs",
            [
                ("New tab", "⌘T"), ("Open location", "⌘L"), ("Close tab", "⌘W"), ("Reopen closed tab", "⇧⌘T"),
                ("Pin or unpin tab", "⌘D"), ("Next / previous tab", "⌥⌘↓ / ⌥⌘↑"), ("Copy URL", "⇧⌘C"),
                ("Clear Today tabs", "⇧⌘K"), ("New tab in split view", "⌃⌘N"),
            ]
        ),
        (
            "Spaces and Window",
            [
                ("Next / previous Space", "⌥⌘→ / ⌥⌘←"), ("Go to Space 1–9", "⌃1 … ⌃9"), ("Show or hide sidebar", "⌘S"),
                ("Switch Space", "Swipe two fingers on the sidebar"), ("New private window", "⇧⌘N"),
            ]
        ),
        (
            "Page",
            [
                ("Back / forward", "⌘[ / ⌘]  or swipe"), ("Reload", "⌘R"), ("Find", "⌘F"), ("Zoom in / out / actual size", "⌘= / ⌘- / ⌘0"),
                ("History", "⌘Y"), ("Bookmark this page", "⇧⌘D"), ("Downloads", "⌥⌘L"), ("Developer tools", "⌥⌘I"),
            ]
        ),
    ]

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.0) { item in
                        LabeledContent(item.0) {
                            Text(item.1).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings › Advanced: import and export, developer tools, versions.
struct AdvancedSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            #if os(macOS)
                Section {
                    LabeledContent("Import") {
                        HStack {
                            Button("From Arc…") { model.requestArcImport() }  // naming: import-reference
                            Button("From Another Browser…") { model.isBrowserImportPresented = true }
                        }
                    }
                    LabeledContent("Sign-ins") {
                        Menu("Stay Signed In From…") {
                            ForEach(ImportSource.allCases.filter { $0.isChromium && $0.dataDirectory.map(Self.exists) == true }) { source in
                                Button(source.displayName) { importSignIns(source) }
                            }
                        }
                        .fixedSize()
                        .accessibilityIdentifier("advanced.signIns")
                    }
                    LabeledContent("Export") {
                        Button("Export Bookmarks…") { exportBookmarks() }
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text(
                        "Sign-ins bring your website cookies over so you stay signed in; macOS asks before Nera can read them. Export saves your bookmarks as a file other browsers can import."
                    )
                    .foregroundStyle(.secondary)
                }
            #endif
            Section {
                Toggle(
                    "Show developer tools",
                    isOn: Binding(get: { model.state.settings.isDeveloperToolsEnabled }, set: { model.setDeveloperTools($0) })
                )
                .accessibilityIdentifier("advanced.devTools")
            } footer: {
                Text(
                    "Adds Inspect Element to the page menu and Developer Tools (⌥⌘I) to the View menu. Pages can never open them on their own."
                )
                .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Nera", value: model.appVersion)
                ForEach(model.pages.registry.engines, id: \.descriptor.id) { engine in
                    LabeledContent(engine.descriptor.displayName, value: engine.descriptor.version)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(SourceAvailability.notice).foregroundStyle(.secondary)
                    if let source = SourceAvailability.repository {
                        Link("Source code", destination: source).accessibilityIdentifier("about.source")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    #if os(macOS)
        private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        private func importSignIns(_ source: ImportSource) {
            Task {
                if let sites = await model.importSignIns(from: source) {
                    model.notice = "You're signed in to \(sites) websites from \(source.displayName)."
                    model.reload()
                } else {
                    model.notice = "Sign-ins weren't imported: access to \(source.displayName)'s key wasn't allowed."
                }
            }
        }

        private func exportBookmarks() {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Nera Bookmarks.html"
            panel.allowedContentTypes = [.html]
            if panel.runModal() == .OK, let url = panel.url { model.exportBookmarks(to: url) }
        }
    #endif
}

/// Clear Browsing Data (⇧⌘⌫): pick what to delete and from when.
struct ClearBrowsingDataView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var range = ClearRange.hour
    @State private var history = true
    @State private var siteData = false

    enum ClearRange: String, CaseIterable, Identifiable {
        case hour = "Last hour"
        case day = "Last 24 hours"
        case week = "Last 7 days"
        case all = "All time"

        var id: String { rawValue }

        var since: Date? {
            switch self {
            case .hour: Date().addingTimeInterval(-3600)
            case .day: Date().addingTimeInterval(-86400)
            case .week: Date().addingTimeInterval(-7 * 86400)
            case .all: nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear Browsing Data").font(.title2.weight(.semibold))
            Picker("Time range", selection: $range) {
                ForEach(ClearRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(maxWidth: 300)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Browsing history", isOn: $history)
                Toggle("Cookies, site data and cache", isOn: $siteData)
                Text("Clearing cookies signs you out of most websites. It applies to all time, in this profile.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Clear Data", role: .destructive) {
                    model.clearBrowsingData(since: range.since, history: history, siteData: siteData)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!history && !siteData)
                .accessibilityIdentifier("clearData.confirm")
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
