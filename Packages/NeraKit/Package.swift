// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
// NeraKit: every module shared by the macOS, iPadOS and iOS apps.
//
// Layers (imports only point down; enforced by scripts/ci/check-architecture.py):
//   L4 Shell        BrowserShell
//   L3 Feature UI   DesignSystem · Sidebar · CommandBar
//   L2 Services     PageLifecycle · Import · Downloads · Permissions · Update · Extensions · Passkeys · SafeBrowsing
//   L1 Engine       EngineKit (contract) · WebKitEngine · ChromiumEngine (adapters)
//   L0 Foundation   BrowserCore · SecurityPolicy · Storage · Networking · Diagnostics · BrowserData
//   Test-only       TestSupport · EngineTestSupport · EngineConformance
//
// Engine adapters are imported ONLY by the app targets (composition roots) and their own tests.
// That is what lets Chromium replace WebKit without touching any UI or business logic.
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "NeraKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // What the app targets link. Everything else is internal to the package.
        .library(name: "BrowserShell", targets: ["BrowserShell"]),
        .library(name: "WebKitEngine", targets: ["WebKitEngine"]),
        .library(name: "ChromiumEngine", targets: ["ChromiumEngine"]),
        .library(name: "Passkeys", targets: ["Passkeys"]),
        // Test-only: the macOS app's Debug-only engine self-test (`--engine-self-test`) runs it against real
        // Chromium and WebKit. Never referenced by Release code.
        .library(name: "EngineConformance", targets: ["EngineConformance"]),
    ],
    targets: [
        // L0 Foundation — Foundation/Observation only; portable to Linux.
        .target(name: "BrowserCore", swiftSettings: strict),
        .target(name: "SecurityPolicy", swiftSettings: strict),
        .target(name: "Storage", dependencies: ["BrowserCore"], swiftSettings: strict),
        .target(name: "Networking", swiftSettings: strict),
        .target(name: "Diagnostics", swiftSettings: strict),

        // L1 Engine — the contract, and one adapter per engine.
        .target(name: "EngineKit", dependencies: ["SecurityPolicy"], swiftSettings: strict),
        .target(name: "WebKitEngine", dependencies: ["EngineKit", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "ChromiumEngine", dependencies: ["EngineKit", "SecurityPolicy"], swiftSettings: strict),

        // L2 Services — engine-neutral logic.
        .target(name: "PageLifecycle", dependencies: ["BrowserCore", "EngineKit", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "BrowserData", swiftSettings: strict),
        .target(name: "Import", dependencies: ["BrowserCore", "BrowserData"], swiftSettings: strict),
        .target(name: "Downloads", swiftSettings: strict),
        .target(name: "Permissions", dependencies: ["BrowserCore", "EngineKit", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "Update", dependencies: ["Networking"], swiftSettings: strict),
        .target(name: "Extensions", dependencies: ["Networking"], swiftSettings: strict),
        .target(name: "Passkeys", dependencies: ["EngineKit", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "SafeBrowsing", dependencies: ["Networking"], swiftSettings: strict),

        // L3 Feature UI — views over state + callbacks; no engine, no app model.
        .target(name: "DesignSystem", dependencies: ["BrowserCore", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "Sidebar", dependencies: ["BrowserCore", "SecurityPolicy", "DesignSystem"], swiftSettings: strict),
        .target(name: "CommandBar", dependencies: ["BrowserCore", "SecurityPolicy", "DesignSystem"], swiftSettings: strict),

        // L4 Shell — wiring, windows, menus. Receives engines from the app; never constructs one.
        .target(
            name: "BrowserShell",
            dependencies: [
                "BrowserCore", "SecurityPolicy", "Storage", "EngineKit", "PageLifecycle",
                "Import", "BrowserData", "Downloads", "Permissions", "Extensions", "Update", "SafeBrowsing", "Networking", "DesignSystem",
                "Sidebar", "CommandBar",
            ],
            swiftSettings: strict
        ),

        // Test-only support libraries (never linked into the apps).
        .target(name: "EngineTestSupport", dependencies: ["EngineKit", "SecurityPolicy"], swiftSettings: strict),
        .target(name: "TestSupport", dependencies: ["BrowserCore"], swiftSettings: strict),
        .target(name: "EngineConformance", dependencies: ["EngineKit", "SecurityPolicy"], swiftSettings: strict),

        // Tests
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore", "TestSupport", "EngineTestSupport"]),
        .testTarget(
            name: "StorageTests", dependencies: ["Storage", "BrowserCore", "TestSupport", "EngineTestSupport"],
            resources: [.copy("Fixtures")]),
        .testTarget(name: "SecurityPolicyTests", dependencies: ["SecurityPolicy", "EngineTestSupport"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"]),
        .testTarget(
            name: "ImportTests", dependencies: ["Import", "BrowserData", "BrowserCore", "TestSupport", "EngineTestSupport"],
            resources: [.copy("Fixtures")]),
        .testTarget(name: "BrowserDataTests", dependencies: ["BrowserData"]),
        .testTarget(name: "DownloadsTests", dependencies: ["Downloads"]),
        .testTarget(
            name: "BrowserShellTests",
            dependencies: [
                "BrowserShell", "BrowserCore", "CommandBar", "PageLifecycle", "Storage", "TestSupport", "EngineTestSupport", "SafeBrowsing",
            ]),
        .testTarget(name: "ExtensionsTests", dependencies: ["Extensions"]),
        .testTarget(name: "SafeBrowsingTests", dependencies: ["SafeBrowsing"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PasskeysTests", dependencies: ["Passkeys", "SecurityPolicy", "EngineKit"]),
        .testTarget(name: "UpdateTests", dependencies: ["Update", "Networking"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PermissionsTests", dependencies: ["Permissions", "BrowserCore", "EngineKit", "SecurityPolicy"]),
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit", "SecurityPolicy"]),
        .testTarget(
            name: "PageLifecycleTests",
            dependencies: ["PageLifecycle", "BrowserCore", "EngineKit", "SecurityPolicy", "TestSupport", "EngineTestSupport"]),
        .testTarget(name: "WebKitEngineTests", dependencies: ["WebKitEngine", "EngineKit", "SecurityPolicy", "EngineConformance"]),
        .testTarget(name: "ChromiumEngineTests", dependencies: ["ChromiumEngine", "EngineKit", "EngineConformance"]),
    ]
)
