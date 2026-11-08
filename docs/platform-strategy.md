# Platform strategy: Mac, iPad, iPhone

Decision record: [ADR-0006](adr/0006-engine-strategy-v2.md).

| Platform | Engine | Extensions | Outer sandbox | Distribution |
|---|---|---|---|---|
| macOS | **Chromium (CEF), default**; WebKit as fallback | Chrome extensions (ADR-0009) | Hardened runtime + library validation; engine sandboxes for all web content; no App Sandbox (Chromium requirement) | Developer ID + notarization + Sparkle |
| iPadOS / iOS | WebKit (App Store rule 2.5.6) | Safari Web Extensions (later) | App Sandbox (always) | App Store / TestFlight |
| iPadOS / iOS (EU) | WebKit; own engine via BrowserEngineKit possible later (IOS-009) | — | App Sandbox | App Store (EU) |
| visionOS (later) | WebKit | — | App Sandbox | App Store |

## What's shared

Everything except the engine adapter and a small amount of platform chrome: models, reducers, storage, security policy, import, sync, downloads/history logic, intelligence, and ~90% of the SwiftUI views (`#if os(macOS)` only for window chrome, hover and the menu bar). One `@main` (`Apps/Shared/NeraApp.swift`).

## Per-platform UX

| | Mac | iPad | iPhone |
|---|---|---|---|
| Sidebar | Always-on vertical sidebar, hideable (⌘S) | Split-view sidebar; slide-over in compact | List of Spaces + tabs; swipe between Spaces |
| Command bar | ⌘T / ⌘L overlay | Same, with hardware-keyboard shortcuts | Bottom search field (thumb reach) |
| Split View | Side by side | Side by side | — |
| Little window / Peek | Floating mini window | Slide-over | Sheet |
| Default browser | `http/https` URL types | Needs Apple's `com.apple.developer.web-browser` entitlement | Same |

## Release order

1. **macOS** (Chromium default): the people who want this kind of browser are mostly on Mac.
2. **iPadOS**: closest to Mac UX (sidebar + keyboard).
3. **iPhone**: companion first (synced Spaces and pinned tabs), then a full browser.
4. visionOS: optional, mostly free from the shared code.
