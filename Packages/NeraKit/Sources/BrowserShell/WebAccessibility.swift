// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Assistive apps and web pages (A11Y-009). WebKit always exposes pages to VoiceOver, Voice Control and Switch
/// Control. Chromium only does when it starts with page accessibility (its per-page switch has no effect in CEF's
/// Alloy style), which costs memory and CPU on every page, so Nera turns it on only when such an app is in use:
/// VoiceOver or Switch Control on at start, or this setting. An assistive app showing up mid-session turns the
/// setting on and Nera offers to restart.
public enum WebAccessibility {
    /// The setting (UserDefaults): start Chromium with page accessibility.
    public static let defaultsKey = "NeraWebAccessibility"
    /// Posted by the app's Chromium bridge (`NRAChromiumAccessibilityNeedsRestart`, same name).
    public static let needsRestart = Notification.Name("NeraWebAccessibilityNeedsRestart")

    /// The running Chromium.
    public enum ChromiumState: Sendable {
        /// Not started yet, or couldn't start: it will start with whatever the setting says.
        case notRunning
        /// Started with page accessibility.
        case withAccessibility
        /// Started without it.
        case withoutAccessibility
    }

    /// The running Chromium's state; nil without Chromium (WebKit always exposes pages). Set by the app.
    nonisolated(unsafe) public static var chromiumState: (() -> ChromiumState)?

    /// Whether the setting differs from what the running Chromium does, so it applies only after a restart.
    static func restartNeeded(setting: Bool, chromium: ChromiumState?) -> Bool {
        switch chromium {
        case .withAccessibility: !setting
        case .withoutAccessibility: setting
        case .notRunning, nil: false
        }
    }
}

/// What the window and Settings show about assistive apps.
public struct AssistiveAppsState: Sendable {
    /// An assistive app appeared after Chromium started without page accessibility: the banner offers a restart.
    public var restartSuggested = false
    /// Bumped when the setting changes (it lives in UserDefaults), so views reading it update.
    var settingRevision = 0
}

extension AppModel {
    /// Settings › General › Accessibility: let assistive apps read pages in Chromium (from the next start).
    public var letsAssistiveAppsReadPages: Bool {
        get {
            _ = assistive.settingRevision  // observed
            return UserDefaults.standard.bool(forKey: WebAccessibility.defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: WebAccessibility.defaultsKey)
            assistive.settingRevision += 1
        }
    }

    /// The setting applies after a restart (Settings shows "Restart Nera to Apply").
    public var assistiveSettingNeedsRestart: Bool {
        WebAccessibility.restartNeeded(setting: letsAssistiveAppsReadPages, chromium: WebAccessibility.chromiumState?())
    }

    /// An assistive app appeared while Chromium can't expose pages to it: offer a restart (the bridge has already
    /// turned the setting on).
    func followAssistiveApps() {
        NotificationCenter.default.addObserver(forName: WebAccessibility.needsRestart, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.assistive.settingRevision += 1
                self?.assistive.restartSuggested = true
            }
        }
    }
}

#if canImport(SwiftUI)
    import SwiftUI

    /// Over the top of the window when VoiceOver (or another assistive app) turned on after Chromium started. "Not Now"
    /// hides only the banner: Settings still offers the restart.
    struct AssistiveRestartBanner: View {
        @Bindable var model: AppModel

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "accessibility").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Restart Nera so assistive apps can read pages").font(.callout.weight(.semibold))
                    Text("VoiceOver or another assistive app turned on. Your tabs come back after the restart.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Not Now") { model.assistive.restartSuggested = false }.buttonStyle(.borderless)
                Button("Restart Nera") { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("assistive.restart")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(12)
            .frame(maxWidth: 620)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("assistive.banner")
            .onAppear {
                AccessibilityNotification.Announcement("Restart Nera so assistive apps can read web pages. Restart button available.")
                    .post()
            }
        }
    }
#endif
