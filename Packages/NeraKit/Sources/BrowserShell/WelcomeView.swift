// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import Import
import SwiftUI

#if os(macOS)
    import AppKit
    import BrowserData
#endif

/// The first-launch welcome: a few calm steps over a slowly moving light. Set Nera up on the Mac, turn on
/// blocking, bring everything over from another browser, and pick a look. Return continues, Escape goes back.
struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var flow: OnboardingFlow
    @Namespace private var nera
    @Environment(\.colorScheme) private var scheme

    init(model: AppModel) {
        self.model = model
        _flow = State(initialValue: OnboardingFlow(model: model))
    }

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        GeometryReader { geo in
            let metrics = WelcomeMetrics(size: geo.size)
            ZStack {
                AuroraCanvas(progress: flow.progress, mood: AuroraCanvas.mood(for: flow.step, theme: flow.theme))
                VStack(spacing: 0) {
                    WelcomeTopBar(flow: flow)
                    // In short windows the step scrolls, so the main button is never pushed off the window.
                    GeometryReader { area in
                        ScrollView(.vertical) {
                            WelcomeStepContent(flow: flow, nera: nera)
                                .frame(maxWidth: .infinity, minHeight: area.size.height)
                                .padding(.horizontal, 40)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    LightButton(title: primaryTitle, isEnabled: canContinue, isBusy: flow.isImporting) { flow.next() }
                        .accessibilityIdentifier(flow.step == .theme ? "welcome.done" : "welcome.continue")
                        .padding(.top, metrics.isCompact ? 14 : 20)
                        .padding(.bottom, metrics.isCompact ? 26 : 38)
                }
            }
            .environment(\.welcomeMetrics, metrics)
        }
        .foregroundStyle(palette.ink)
        .ignoresSafeArea()
        .animation(.spring(response: 0.6, dampingFraction: 0.86), value: flow.step)
        .background {
            Button("Back") { flow.back() }.keyboardShortcut(.cancelAction).opacity(0).disabled(!flow.canGoBack)
        }
        .accessibilityIdentifier("welcome")
    }

    private var primaryTitle: String {
        switch flow.step {
        case .intro: "Get Started"
        case .source: flow.source == nil ? "Choose a Browser" : "Continue"
        case .summary: flow.summary == nil ? "Importing…" : "Continue"
        case .theme: flow.needsRelaunch ? "Restart and Start Browsing" : "Start Browsing"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch flow.step {
        case .source: flow.source != nil
        case .spaces: !flow.pickedSpaces.isEmpty
        case .summary: flow.summary != nil
        default: true
        }
    }
}

/// Back (beside the window's buttons), the progress dots, and Skip.
struct WelcomeTopBar: View {
    let flow: OnboardingFlow
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        ZStack {
            ProgressDots(stage: flow.stage, count: OnboardingFlow.stageCount)
            HStack {
                if flow.canGoBack {
                    GlassCircleButton(symbol: "chevron.left", label: "Back") { flow.back() }
                        .accessibilityIdentifier("welcome.back")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                Spacer()
                if flow.canSkip {
                    Button("Skip") { flow.skip() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 10).frame(height: 26)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("welcome.skip")
                        .transition(.opacity)
                }
            }
            .padding(.leading, 80)  // the window's buttons sit to the left
            .padding(.trailing, 18)
        }
        .frame(height: 30)  // centered on the window's buttons
        .padding(.top, 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: flow.canGoBack)
    }
}

/// One dot per part of the welcome; the current one stretches and fills with light.
struct ProgressDots: View {
    let stage: Int
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == stage ? AnyShapeStyle(Spectrum.ring) : AnyShapeStyle(palette.ink.opacity(i < stage ? 0.45 : 0.15)))
                    .frame(width: i == stage ? 22 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: stage)
        .accessibilityElement()
        .accessibilityLabel("Step \(stage + 1) of \(count)")
    }
}

/// The current step, with a short lift-and-fade between steps.
struct WelcomeStepContent: View {
    @Bindable var flow: OnboardingFlow
    let nera: Namespace.ID

    var body: some View {
        Group {
            switch flow.step {
            case .intro: IntroStep(nera: nera)
            case .essentials: EssentialsStep(flow: flow)
            case .privacy: PrivacyStep(flow: flow)
            case .source: SourceStep(flow: flow, nera: nera)
            case .spaces: SpacesStep(flow: flow)
            case .extensions: ExtensionsStep(flow: flow)
            case .favorites: FavoritesStep(flow: flow)
            case .summary: SummaryStep(flow: flow, nera: nera)
            case .theme: ThemeStep(flow: flow)
            }
        }
        .id(flow.step)
        .transition(
            .asymmetric(
                insertion: .offset(x: flow.isForward ? 48 : -48).combined(with: .opacity),
                removal: .offset(x: flow.isForward ? -48 : 48).combined(with: .opacity)))
    }
}

extension ImportSource {
    /// The browser's Mac app, for its icon (Arc is found by its app name instead).
    var bundleID: String? {
        switch self {
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .firefox: "org.mozilla.firefox"
        case .arc, .bookmarksFile: nil
        }
    }

    /// The browser's app icon, when it's installed.
    @MainActor var appIcon: Image? {
        #if os(macOS)
            if let bundleID { return Image.app(bundleID) }
            let app = URL(fileURLWithPath: "/Applications/\(displayName).app")
            guard FileManager.default.fileExists(atPath: app.path) else { return nil }
            return Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
        #else
            nil
        #endif
    }

    /// A short name for tiles.
    var shortName: String {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Edge"
        default: displayName
        }
    }
}
