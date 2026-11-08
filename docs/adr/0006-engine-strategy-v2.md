# ADR-0006: Engine strategy v2 — Chromium default on macOS, WebKit on iOS, engine independence

**Status:** Accepted · **Date:** 2026-10-25 · **Supersedes:** [ADR-0002](0002-engine-strategy-v1.md) · **Amended by:** [ADR-0009](0009-chromium-go-no-go.md) (Renderer-only JIT, own Keychain item, extension hosting model)

## Context

- Chrome-extension compatibility is a core reason people choose a browser. Extensions only exist on Chromium.
- iOS/iPadOS must use WebKit (App Store rule 2.5.6), except for EU-only builds using BrowserEngineKit.
- ADR-0002 put Chromium in "Phase 2". Retrofitting a second engine later would mean redesigning every abstraction (tabs, navigation, permissions, downloads, extensions, DevTools). The maintainer directed that Chromium be designed in from week 1.

## Decision

1. **macOS: Chromium is the default engine**, embedded via **CEF** (starting at CEF 156.0.14 / Chromium 156.0.8078.48, Oct 2026).
2. **iOS/iPadOS: WebKit.**
3. **macOS keeps WebKit as a fallback engine** for testing, diagnostics, per-site escape hatches (e.g. a Chromium regression on one site, or DRM until Widevine is licensed), and future flexibility.
4. **Engine independence is a core architectural principle:** no business logic, UI or feature module may depend on WebKit or Chromium APIs. Only the `WebKitEngine` and `ChromiumEngine` adapters may, and a CI layering check enforces it.
5. One contract (`EngineKit`) and one **conformance suite** that every engine must pass. A feature isn't done until it passes on both engines (where it applies).
6. The engine is chosen **per profile** (default Chromium on macOS), and the Developer menu has "Reopen this tab in the fallback engine".

## Security profile on macOS (precise statement)

Chromium is a multi-process application with its own sandbox architecture. On macOS, the Chromium **main (browser) process** needs capabilities that Apple's App Sandbox denies (Mach-port rendezvous between processes, its own `sandbox_init` profiles for children). So, like Chrome, Arc and Brave:

- the **main app** ships with the **Hardened Runtime and library validation, without the App Sandbox**;
- **renderer, GPU and utility processes run inside Chromium's own seatbelt sandbox**, with **site isolation** on;
- the **WebKit fallback** keeps WebKit's own sandboxed WebContent processes;
- entitlements are **allowlisted per bundle** (main app and each helper). Only renderer/GPU helpers may hold `com.apple.security.cs.allow-jit`. Anything else needs measured evidence and an ADR amendment;
- the forbidden Chromium switches `--no-sandbox`, `--disable-web-security`, `--ignore-certificate-errors`, `--disable-site-isolation-trials`, `--allow-running-insecure-content` and `--remote-debugging-port` are rejected in Release builds.

This is not "Chromium is insecure". Apple's App Sandbox and Chromium's sandbox model don't align, and web content stays sandboxed either way. iOS builds keep the full App Sandbox (always required there).

## Integration approach

- `ChromiumEngine` is an Xcode framework target (not SwiftPM). It links `Chromium Embedded Framework.framework` and `libcef_dll_wrapper.a`, with five helper apps (`Nera Helper`, `(Renderer)`, `(GPU)`, `(Plugin)`, `(Alerts)`).
- The bridge is ObjC++ (`.mm`) exposing a small ObjC API to Swift. CEF's ref-counted C++ API is impractical to use from Swift directly.
- An `NSApplication` subclass conforming to `CefAppProtocol` is set as `NSPrincipalClass` (works with the SwiftUI `App` lifecycle). The message loop is integrated via `external_message_pump`.
- CEF binaries are downloaded by `scripts/engine/fetch-cef.sh` with a **pinned version and SHA-256**, cached outside the repo, never committed.

## Known risks → questions for a CEF prototype

| # | Question | If the answer is "no" |
|---|---|---|
| 1 | Can a Chrome-style CEF browser be hosted in our own NSView **without Chrome's UI**, while MV3 extensions (uBlock Origin Lite, Bitwarden, 1Password) install and work? | Alloy style + our own extension host, or a direct Chromium `content/` fork (needs a dedicated team). Decided in a follow-up ADR |
| 2 | How much breaks without H.264/AAC (standard CEF builds exclude proprietary codecs for patent reasons)? | Custom CEF build with `proprietary_codecs` (patent licensing for proprietary codecs), or route affected sites to WebKit |
| 3 | Widevine DRM: what does licensing + VMP signing require? Does FairPlay work in our macOS WKWebView? | Route DRM sites to WebKit until licensed |
| 4 | Safe Browsing for Chromium: the Google API is non-commercial only; Web Risk is the commercial option | Choose before any revenue (release signoff SIGN-010) |
| 5 | Does CEF's message pump run inside the SwiftUI/AppKit loop with no input lag or jank? | Dedicated pump scheduling via `OnScheduleMessagePumpWork` |

## Consequences

- The macOS app grows from ~4 MB to ~150–300 MB, so a size budget is set from measurements.
- No Mac App Store distribution for the default macOS build (Developer ID + notarization + Sparkle instead).
- One extra maintenance duty: the Chromium **security rebase SLA**, ≤7 days after each CEF stable security release and ≤48 h for exploited-in-the-wild bugs ([checklist 006](../../checklists/006-chromium-upgrade.md)).
- Two engines on macOS double the conformance-test runtime. Accepted: it's the price of engine independence.
