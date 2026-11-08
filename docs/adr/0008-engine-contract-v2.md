# ADR-0008: Engine contract v2

**Status:** Accepted · **Date:** 2026-10-26 · **Context:** [ADR-0006](0006-engine-strategy-v2.md) (Chromium default on macOS, WebKit on iOS, engine independence)

## Problem

The first contract (`load`, `goBack`, four callbacks) was shaped by WebKit and missed most of what a browser engine asks of its host: dialogs, file pickers, downloads, permissions, authentication, certificate errors, popups, crashes. Several of those were **silent bugs**: `alert()` was dropped, `<input type=file>` did nothing on macOS, downloads were impossible. Retrofitting these later, once a second engine exists, is exactly the technical debt this project wants to avoid.

## Decision

The contract in `EngineKit` is designed against **both** WebKit's (`WKNavigationDelegate`, `WKUIDelegate`, `WKDownloadDelegate`) and CEF's (`CefRequestHandler`, `CefLifeSpanHandler`, `CefJSDialogHandler`, `CefDialogHandler`, `CefDownloadHandler`, `CefPermissionHandler`) host APIs. The mapping table is in [architecture.md](../architecture.md#engine-contract-v2).

1. **Two protocols, nothing else crosses the boundary.** `BrowserEngine` (factory + capabilities + data removal) and `WebPage` (one page). The only platform type is `PlatformView`. Engine types never appear in signatures, and CI rejects `WK*`/`Cef*` outside the adapters.
2. **State is one value.** `PageState` (committed URL, title, loading, progress, history, security, zoom, audio, capture) is `Equatable`, so UI diffs and tests are trivial, and every engine reports the same shape.
3. **Three channels from page to app** (`WebPageDelegate`):
   - `pageDidChangeState`: the state changed;
   - `didEmit(PageEvent)`: informational, needs no answer (navigation lifecycle, blocked navigations, crashes, downloads, `window.close()`);
   - `didRequest(PageRequest)`: needs an answer (permission, download destination, dialog, file chooser, HTTP auth, certificate error, external app, child page).
4. **Every request carries a one-shot `Decision<Answer>` that is default-deny.** The first answer wins. **Releasing an unanswered decision applies its fallback** (deny, cancel, discard): the decision's `deinit` hands the fallback to the main actor (immediately when released on the main thread, which is always the case in Nera). We first used Swift 6.2 `isolated deinit`, but Swift 6.3.3's optimizer crashes on it for generic classes in Release builds, so the hop lives in a small box type instead. Revisit when the compiler bug is fixed. A closed page, a discarded tab or a forgotten prompt can never grant anything. This turns a whole class of security bugs into impossibilities.
5. **Capabilities, not engine checks.** `EngineCapabilities` (a `Set<EngineCapability>`) declares optional features. Features and conformance cases check capabilities; CI rejects `#if canImport(WebKit)` outside adapters.
6. **Child pages keep their opener.** `window.open`/`target=_blank` produce a `NewPageRequest` carrying a page the *engine* created, so `window.opener` and OAuth popup flows work on both engines (WebKit's `createWebViewWith` and CEF's `OnBeforePopup` both require the engine to create it). The app adopts it or it's closed.
7. **Security stays above the engine.** Adapters must run the shared `NavigationPolicy` for user-initiated loads and page-initiated navigations. Server-trust challenges always get system default handling (SR-002). Certificate bypass is a capability WebKit doesn't declare.
8. **Engines are chosen only at the composition root.** The app target lists engines in preference order (`[ChromiumEngine(), WebKitEngine()]` on macOS). `EngineRegistry` picks per profile (`Profile.engine`, default = first *available* engine). Chromium is listed first today and reports itself unavailable, so switching engines changes no UI or business logic.
9. **One conformance suite** (`EngineConformance`) runs against every engine, with `data:` URLs only (deterministic, offline). Results render into [checklist 005](../../checklists/005-browser-engine.md). A case needing an undeclared capability reports "unsupported", never a silent pass.

## Engine-neutral services built on it (PageLifecycle)

`PageManager` owns pages for every engine: lazy creation, LRU cap, memory-pressure discard (warning → older half, critical → all background), idle suspension, crash tracking with a reload path, per-tab request queues, dialog flood protection (`DialogThrottle`), child-page adoption, download destination via `DownloadPlanner` (sanitized names, never overwrite).

## Consequences

- WebKit fixes: dialogs, file chooser, downloads, permission prompts, HTTP auth, cert-error interstitial, crash recovery, popups with opener, find, zoom.
- Not yet covered by conformance (needs `LocalTestServer` or real gestures): permissions, file chooser, auth, certificate errors, child pages, HTTPS upgrade, profile isolation. The adapter code exists and the app-side logic is tested with the fake engine.
- Adding an engine = implementing two protocols, passing the suite, and adding one line to the app's composition root.
- Changing the contract = updating both adapters, the fake, and the conformance suite in the same PR ([API design](../standards/api-design.md)).

## Rejected alternatives

- **Callbacks struct (the first design):** no answer path, no default-deny, grows into a god object.
- **Async streams for events:** awkward for requests that need synchronous engine answers (WebKit's `createWebViewWith` must return immediately).
- **One protocol per request type:** many more delegate methods per engine for no gain over a typed enum.
