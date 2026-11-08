# ADR-0002 (superseded): Engine strategy v1 — WebKit first, Chromium on macOS in Phase 2

**Status:** Superseded by [ADR-0006](0006-engine-strategy-v2.md) · **Date:** 2026-10-25

## Context

- Arc users depend on **Chrome extensions** (password managers, ad blockers, dev tools). Those only exist on Chromium.
- On **iOS/iPadOS**, App Store rules require WebKit, except for EU-only apps using `BrowserEngineKit`. So one engine everywhere is not possible.
- Building and maintaining a Chromium fork costs one full-time engineer minimum (100 GB checkout, multi-hour builds, a security rebase every 4 weeks).

## Decision

1. All UI and data code talks only to `EngineKit` protocols (`BrowserEngine`, `WebPage`). No WebKit or Chromium types leak into `NeraCore` or `NeraUI`.
2. **Phase 1 (MVP, all platforms): WebKit** (`WebKitEngine`). It ships in weeks, is tiny (≈4 MB app, where Chromium-based browsers ship hundreds of MB), is security-patched by Apple through OS updates, and gives the same engine on Mac, iPad and iPhone.
3. **Phase 2 (macOS): Chromium** as a second `BrowserEngine` (`ChromiumEngine`), built on Chromium's `content/` layer with a thin ObjC++ bridge. It unlocks Chrome extensions. Users can pick an engine per profile.
4. Evaluate **CEF** (Chromium Embedded Framework) first, because it's faster to integrate. Move to a direct `content/` fork only if CEF blocks extension support or performance goals.
5. Navigation security lives in `SecurityKit`, so both engines enforce identical rules.

## Consequences

- Fast first release, small team, and the same features on Apple's three platforms.
- Chrome-extension parity waits for Phase 2. Our migration message has to be honest about that.
- The `WebPage` protocol has to stay small and behavior-focused. New engine features go in as capabilities (`supportsExtensions`, …) instead of leaking engine types.
