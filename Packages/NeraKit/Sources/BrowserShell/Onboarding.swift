// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import BrowserData
import Foundation
import Import
import Observation

/// The welcome screen's state: which step is showing, what the user picked, and what was imported.
/// Nothing on the Mac changes until the user presses Continue on a step.
@MainActor
@Observable
final class OnboardingFlow {
    /// The steps, in order. Some are skipped (Spaces only for Arc, Extensions only when there are any).
    enum Step: Int, CaseIterable, Comparable {
        case intro, essentials, privacy, source, spaces, extensions, favorites, summary, theme

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    let model: AppModel
    private(set) var step = Step.intro
    private var trail: [Step] = []
    /// Moving forward (content slides left) or back.
    private(set) var isForward = true

    // Essentials
    var makeDefault = true
    var addToDock = true
    var openAtLogin = false
    let isAlreadyDefault: Bool
    let isAlreadyInDock: Bool

    // Privacy
    var blockTrackers = true

    // Import
    var source: ImportSource?
    private(set) var arcPreview: (library: ArcImporter.Result, archive: [ArchivedTab])?
    var pickedSpaces: Set<UUID> = []
    var includeArchive = true
    var includeHistory = true
    /// Bring website sign-ins (cookies) over too, so the user stays signed in.
    var includeSignIns = true
    private(set) var foundExtensions: [FoundExtension] = []
    var pickedExtensions: Set<String> = []
    private(set) var summary: ImportSummary?
    private(set) var isImporting = false
    /// "Start Browsing" was pressed.
    private var isFinishing = false

    // Start fresh
    var pickedFavorites: Set<URL> = Set(WelcomeSuggestions.sites.prefix(4).map(\.url))

    // Make it yours
    var theme = SpaceTheme.swatches[1]

    /// Extensions being installed in the background (the blocker, then imported ones).
    private var installs: Task<Int, Never>?
    private(set) var installedCount = 0

    init(model: AppModel) {
        self.model = model
        #if os(macOS)
            isAlreadyDefault = DefaultBrowser.isDefault
            isAlreadyInDock = MacIntegration.isInDock
            openAtLogin = MacIntegration.opensAtLogin
        #else
            isAlreadyDefault = false
            isAlreadyInDock = false
        #endif
        if let current = model.state.selectedSpace?.theme, current.grain != nil { theme = current }
        #if DEBUG && os(macOS)
            DemoMode.prepare(self)
        #endif
    }

    #if DEBUG
        /// Demo mode: shows a step with made-up import data (never the Mac's real browser data).
        func showDemo(
            _ step: Step, source: ImportSource, preview: (library: ArcImporter.Result, archive: [ArchivedTab]),
            extensions: [FoundExtension], summary: ImportSummary?
        ) {
            self.source = source
            arcPreview = preview
            pickedSpaces = Set(preview.library.spaces.map(\.id))
            foundExtensions = extensions
            pickedExtensions = Set(extensions.filter(\.wasEnabled).map(\.id))
            self.summary = summary
            trail = step == .intro ? [] : [.intro]
            self.step = step
        }
    #endif

    /// Sources offered on the import step: installed browsers, Arc first.
    var sources: [ImportSource] {
        #if os(macOS)
            let order: [ImportSource] = [.arc, .chrome, .safari, .brave, .edge, .firefox]  // naming: import-reference
            return order.filter { $0 == .arc ? model.isArcInstalled : ($0 == .safari || $0.isInstalled) }
        #else
            return []
        #endif
    }

    /// 0...1 through the flow, for the progress line.
    var progress: Double { Double(stage) / Double(Self.stageCount - 1) }

    var canGoBack: Bool { !trail.isEmpty && step != .summary }

    /// Whether the current step offers Skip.
    var canSkip: Bool { [.essentials, .source, .extensions, .favorites].contains(step) }

    /// Parts of the welcome, for the progress dots: hello, Mac, privacy, import, look.
    static let stageCount = 5

    /// The part the current step belongs to.
    var stage: Int {
        switch step {
        case .intro: 0
        case .essentials: 1
        case .privacy: 2
        case .source, .spaces, .extensions, .favorites, .summary: 3
        case .theme: 4
        }
    }

    // MARK: Moving between steps

    func go(to next: Step) {
        trail.append(step)
        isForward = true
        step = next
    }

    func back() {
        guard let previous = trail.popLast() else { return }
        isForward = false
        step = previous
    }

    /// Continue on the current step: applies its choices, then moves on.
    func next() {
        switch step {
        case .intro: go(to: .essentials)
        case .essentials:
            applyEssentials()
            go(to: .privacy)
        case .privacy:
            if blockTrackers { install([AppModel.blockerExtensionID]) }
            go(to: sources.isEmpty ? .favorites : .source)
        case .source: chooseSource()
        case .spaces:
            if foundExtensions.isEmpty {
                go(to: .summary)
                runImport()
            } else {
                go(to: .extensions)
            }
        case .extensions:
            install(Array(pickedExtensions))
            go(to: .summary)
            runImport()
        case .favorites:
            model.startFresh(
                favorites: WelcomeSuggestions.sites.map(\.url).filter(pickedFavorites.contains), addWorkSpace: false, finish: false)
            go(to: .theme)
        case .summary: go(to: .theme)
        case .theme: finish()
        }
    }

    /// Skip on the current step: moves on without applying it.
    func skip() {
        switch step {
        case .essentials: go(to: .privacy)
        case .source: go(to: .favorites)
        case .extensions:
            pickedExtensions = []
            go(to: .summary)
            runImport()
        case .favorites: go(to: .theme)
        default: next()
        }
    }

    private func chooseSource() {
        guard let source else { return go(to: .favorites) }
        #if os(macOS)
            foundExtensions = model.extensionsIn(source)
            pickedExtensions = Set(foundExtensions.filter { $0.wasEnabled && $0.isSupported }.map(\.id))
            if source == .arc, let preview = model.previewArc() {  // naming: import-reference
                arcPreview = preview
                pickedSpaces = Set(preview.library.spaces.map(\.id))
                go(to: .spaces)
            } else if !foundExtensions.isEmpty {
                go(to: .extensions)
            } else {
                go(to: .summary)
                runImport()
            }
        #endif
    }

    private func applyEssentials() {
        #if os(macOS)
            if makeDefault, !isAlreadyDefault { DefaultBrowser.makeDefault { _ in } }
            if addToDock, !isAlreadyInDock { MacIntegration.addToDock() }
            if openAtLogin != MacIntegration.opensAtLogin { MacIntegration.setOpensAtLogin(openAtLogin) }
        #endif
    }

    private func install(_ ids: [String]) {
        guard !ids.isEmpty, model.supportsExtensions else { return }
        let previous = installs
        installs = Task { [model] in
            let before = await previous?.value ?? 0
            return before + (await model.installFromWebStore(ids))
        }
    }

    /// Runs the import a moment after the summary appears, so its art can animate while it works.
    private func runImport() {
        guard let source, summary == nil else { return }
        isImporting = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            #if os(macOS)
                var result: ImportSummary
                if source == .arc, let preview = arcPreview {  // naming: import-reference
                    result = model.importArc(preview, spaces: pickedSpaces, archive: includeArchive, history: includeHistory)
                } else {
                    result = model.importOtherBrowser(source)
                }
                if includeSignIns, source.isChromium {
                    // macOS asks the user to allow access to the browser's key here.
                    if let sites = await model.importSignIns(from: source) {
                        result.signIns = sites
                    } else {
                        result.problems.append("Sign-ins")
                    }
                }
                summary = result
            #endif
            isImporting = false
        }
    }

    #if os(macOS)
        /// The browser being imported from has saved passwords (offered a move to Apple Passwords).
        var hasSavedPasswords: Bool {
            guard let source, source.isChromium, let profile = source.dataDirectory else { return false }
            return FileManager.default.fileExists(atPath: profile.appending(path: "Login Data").path)
        }

        /// After moving passwords: Nera fills them through Apple's iCloud Passwords extension.
        func setUpPasswordFilling() {
            let id = PasswordManager.applePasswords.extensionID
            if !model.hasExtension(for: .applePasswords) { install([id]) }
        }
    #endif

    /// The picked look for the first Space, then other ready-made looks of the same lightness for the rest, so
    /// every Space is easy to tell apart (and swiping between them changes the color).
    static func looks(startingWith first: SpaceTheme, count: Int) -> [SpaceTheme] {
        let isDark = first.appearance == .dark
        let others = SpaceTheme.swatches.filter { ($0.appearance == .dark) == isDark && !$0.looksLike(first) && $0.saturation > 0.05 }
        return (0..<count).map { i in
            guard i > 0, !others.isEmpty else { return first }
            var look = others[(i - 1) % others.count]
            look.appearance = first.appearance
            look.grain = first.grain
            return look
        }
    }

    /// Whether finishing restarts Nera (to start newly installed extensions).
    /// Only when Chromium is already running (otherwise it starts after the welcome with the new extensions).
    var needsRelaunch: Bool {
        guard !model.chromiumWaitsForWelcome() else { return false }
        return (blockTrackers && !model.hasBlocker) || !pickedExtensions.isEmpty || model.needsRelaunchForExtensions
    }

    private func finish() {
        guard !isFinishing else { return }  // "Start Browsing" pressed again while extensions finish installing
        isFinishing = true
        for (space, look) in zip(model.state.spaces, Self.looks(startingWith: theme, count: model.state.spaces.count)) {
            model.send(.space(.customize(space.id, icon: nil, theme: look)))
        }
        let installs = installs
        Task {
            let installed = await installs?.value ?? 0
            installedCount = installed
            model.finishWelcome()
            if model.chromiumWaitsForWelcome() {
                // Chromium starts now, with the extensions just installed: no restart. Save the library first, so a
                // crash in Chromium's first start doesn't show the welcome again.
                model.needsRelaunchForExtensions = false
                model.store.flush()
                NotificationCenter.default.post(name: ChromiumStartup.welcomeFinished, object: nil)
                return
            }
            if installed != 0 {
                try? await Task.sleep(for: .milliseconds(600))
                model.relaunch()
            }
        }
    }
}

/// Sites offered as Favorites when starting fresh. Only their addresses are stored; nothing loads until opened.
enum WelcomeSuggestions {
    static let sites: [(name: String, url: URL)] = [
        ("YouTube", "https://www.youtube.com"), ("GitHub", "https://github.com"), ("Gmail", "https://mail.google.com"),
        ("Notion", "https://www.notion.so"), ("Figma", "https://www.figma.com"), ("Spotify", "https://open.spotify.com"),
        ("ChatGPT", "https://chatgpt.com"), ("Claude", "https://claude.ai"), ("Wikipedia", "https://www.wikipedia.org"),
        ("Reddit", "https://www.reddit.com"), ("LinkedIn", "https://www.linkedin.com"), ("X", "https://x.com"),
    ].compactMap { name, string in URL(string: string).map { (name, $0) } }
}
