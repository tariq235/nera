# ADR-0010: ChromiumEngine structure — pure-Swift adapter, CEF bridge in the macOS app

**Status:** Accepted · **Date:** 2026-10-26 · **Amends:** [ADR-0006](0006-engine-strategy-v2.md) ("Integration approach") · **Related:** [ADR-0009](0009-chromium-go-no-go.md), [ADR-0008](0008-engine-contract-v2.md)

## Context

ADR-0006 planned `ChromiumEngine` as an Xcode framework target, because CEF is a 340 MB framework with a C++ wrapper library and five helper apps. That would have moved the adapter out of NeraKit. Plain `swift test` (unit tests, CI's fast job, any machine without CEF) could then no longer build or test it, and the adapter's security-relevant logic would only be testable inside the full app.

The CEF prototype showed the adapter splits cleanly in two:
- **Contract logic in Swift.** It maps Chromium callbacks to `PageEvent` and `PageRequest`, runs `NavigationPolicy` on every navigation, applies default-deny `Decision`s, and maps storage scopes.
- **A thin ObjC++ bridge.** It calls CEF and passes callbacks back, with no CEF types in its header.

## Decision

1. **`ChromiumEngine` stays a pure-Swift module in NeraKit.** It talks to Chromium only through the `ChromiumBackend` / `ChromiumPageHandle` / `ChromiumPageEvents` protocols (a port), which mirror the Chromium bridge.
2. **The CEF bridge lives in the macOS app** (`Apps/macOS/Chromium`, next step). It implements `ChromiumBackend` with ObjC++, along with the helper apps, the `CefAppProtocol` application class, and CEF startup and shutdown. The app's composition root injects it: `ChromiumEngine(backend: CEFBackend.shared)`.
3. **No backend → unavailable.** `ChromiumEngine()` (iOS, `swift test`) reports `isAvailable == false`, and the registry falls back to WebKit, as today.
4. **Two levels of tests:**
   - **Adapter unit tests in NeraKit,** against a fake backend: policy on typed and page-initiated navigations, committed-URL rule, default-deny dialogs and downloads, nothing after close, storage-scope mapping, termination mapping.
   - **The shared conformance suite against real Chromium,** in a test bundle hosted by the macOS app (where CEF and its helpers exist). The generated parity matrix (checklist 005) comes from that run.
5. **Engine-independence rules are unchanged.** Only `ChromiumEngine` and the app's `Apps/macOS/Chromium` bridge may know about CEF, and the architecture check is extended to that directory when it lands.

## Consequences

- NeraKit stays buildable and testable anywhere. The adapter's security logic is covered on every PR, even on machines without CEF.
- The real-Chromium conformance run needs the app build (CEF download, helpers, signing). It runs in CI's app job, not the fast unit job.
- The port is a second API surface to keep in sync with the bridge. It's small (one backend, one page handle, one events protocol), and both sides compile against it, so drift fails the build.
