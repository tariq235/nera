# Architecture principles

These are the rules that keep Nera maintainable for a decade. When a design choice conflicts with one, write an ADR.

## The four ship requirements

Every feature must satisfy all four before it ships (enforced by the [Definition of Done](definition-of-done.md)):

1. **Native performance.** It meets the [performance budget](performance-budget.md) on the reference hardware.
2. **Security by default.** It satisfies the [security requirements](security-requirements.md) with no user configuration.
3. **Privacy by default.** No new data leaves the device unless the user explicitly asks.
4. **Documented and tested.** Docs and checklist rows are updated, and automated tests cover every relevant category, on every engine it applies to.

## Principles

**AP-1 · Engine independence.** No business logic, UI or feature module may depend directly on WebKit or Chromium APIs. Only `WebKitEngine` and `ChromiumEngine` may import them. Features ask for `EngineCapabilities`, never `#if engine`. ([ADR-0006](../adr/0006-engine-strategy-v2.md))

**AP-2 · Layers point down.** L4 Shell → L3 Feature UI → L2 Services → L1 Engine → L0 Foundation. No upward or sideways imports between features; features talk through BrowserCore actions or service protocols. Enforced by `scripts/ci/check-architecture.py`.

```
L4 Shell       BrowserShell
L3 Feature UI  Sidebar · CommandBar · …
L2 Services    Permissions · Downloads · History · Bookmarks · Import · Sync · Extensions · Update · Settings · Diagnostics · Intelligence
L1 Engine      EngineKit · WebKitEngine · ChromiumEngine
L0 Foundation  BrowserCore · SecurityPolicy · Storage · Networking
Test-only      TestSupport
```

**AP-3 · A pure core.** L0 modules import only Foundation, have no global state, and build and test on Linux. State changes are `Action → Reducer → [Effect]`. Side effects run outside the reducer.

**AP-4 · Default deny.** Any request crossing a trust boundary (permissions, downloads, dialogs, external apps, file access) is denied unless explicitly granted. If a request is dropped, it's denied.

**AP-5 · Local first.** The app works fully offline and without an account. Cloud features are optional and end-to-end encrypted.

**AP-6 · Minimal dependencies.** Prefer Apple frameworks. Every third-party package needs an ADR, a license on the allowlist, and an owner. Test-only dependencies stay in test targets.

**AP-7 · Platform-native.** SwiftUI by default, with AppKit/UIKit where SwiftUI lacks control. Respect platform conventions (menus, shortcuts, accessibility, Handoff). No web UI for browser chrome.

**AP-8 · Everything behind a protocol has a test double.** Every service (persistence, engine, networking, clock, UUIDs) is injected, with a fake in `TestSupport`.

**AP-9 · Explicit capabilities over silent degradation.** If an engine or platform can't do something, the feature says so in the UI and in the parity matrix ([checklist 005](../../checklists/005-browser-engine.md)).

**AP-10 · Docs are code.** ADRs for decisions, checklists for status, DocC for public APIs. CI validates them like code.

## Module rules

- A module is created when it has code. Its name, layer and owner are recorded in [architecture.md](../architecture.md).
- Module names never shadow Apple frameworks (`SecurityPolicy`, not `Security`; `Networking`, not `Network`).
- The public API surface is minimal; `internal` is the default. See [API design](api-design.md).
