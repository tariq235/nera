// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserShell
import SwiftUI
import WebKitEngine

#if os(macOS)
    import ChromiumEngine
    import Passkeys
#endif

@main
struct NeraApp: App {
    #if os(macOS)
        /// Starts and stops Chromium around the app's lifecycle (Apps/macOS/Chromium).
        @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    /// Composition root: the **only** place that names concrete engines (ADR-0006, AP-1).
    /// macOS lists Chromium first, backed by the app's CEF bridge (ADR-0010). While Chromium is off or
    /// not running, its adapter reports itself unavailable and the registry falls back to WebKit.
    @State private var model: AppModel = {
        #if os(macOS)
            RenameStartup.migrateFromLumen()  // Lumen → Nera, once; before the store loads and Chromium starts
            return AppModel.live(
                engines: [
                    ChromiumEngine(
                        backend: ChromiumBootstrap.backend,
                        webAuthenticator: SystemPasskeyAuthenticator(isEntitled: SystemPasskeyAuthenticator.bundleIsEntitled)),
                    WebKitEngine(),
                ], safeMode: LaunchSafety.isSafeMode)
        #else
            return AppModel.live(engines: [WebKitEngine()], safeMode: LaunchSafety.isSafeMode)
        #endif
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { model.openFromOutside($0) }  // links from other apps and Finder (default browser)
                #if os(macOS)
                    .frame(minWidth: 820, minHeight: 520)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        model.store.flush()
                        LaunchSafety.launchSucceeded()
                        model.installPendingUpdateOnQuit()  // a verified, staged update takes this version's place
                    }
                #endif
        }
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.store.flush() }
        }
        .commands { BrowserCommands(model: model) }

        #if os(macOS)
            // ⇧⌘N: private windows share the engines, never the library, history or website data.
            WindowGroup("Private Browsing", id: AppModel.privateWindowID) {
                PrivateWindowRoot(registry: model.pages.registry)
                    .frame(minWidth: 820, minHeight: 520)
            }
            .handlesExternalEvents(matching: [])  // links from other apps never open private windows
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))

            // Links from other apps (Settings › Links): a small window, one click from becoming a tab.
            WindowGroup("Little Window", id: AppModel.littleWindowID, for: UUID.self) { $id in
                if let id { LittleWindowView(model: model, id: id) }
            }
            .handlesExternalEvents(matching: [])
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 980, height: 680)

            Settings { SettingsView(model: model) }
        #endif
    }
}
