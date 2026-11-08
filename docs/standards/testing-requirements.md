# Testing requirements

"Flawless and smooth" means bugs get caught before users see them. Every category below exists and is automated. They run in **tiers**, so the PR gate stays fast while slow suites still run every night and before every release.

## Categories & tiers

| Category | Tool | What it proves | PR gate | Nightly | Release |
|---|---|---|---|---|---|
| Unit | Swift Testing | Reducers, policies, parsers, storage | ✅ | ✅ | ✅ |
| Integration | Swift Testing + `TestSupport` | Store ⇄ engine ⇄ storage wiring | ✅ | ✅ | ✅ |
| Engine conformance | `EngineConformance` | Every engine meets the contract (WebKit + Chromium); the fake engine is checked by PageLifecycle tests | ✅ | ✅ | ✅ |
| Security conformance | `LocalTestServer` suite | HTTPS-Only, HSTS, CSP, COOP/COEP, nosniff, SameSite, mixed content, cert errors, on both engines | ✅ | ✅ | ✅ |
| UI | XCUITest | Real app, real engine, keyboard-driven flows | smoke | full | full |
| Accessibility | `performAccessibilityAudit()` | No audit failures on main screens | ✅ | ✅ | ✅ |
| Snapshot | swift-snapshot-testing (test targets only) | Light/dark, large text, high contrast | ✅ | ✅ | ✅ |
| Import | fixture suites | Arc, Chrome, Safari importers | ✅ | ✅ | ✅ |
| Migration | per-schema-version fixtures | Every old library format loads | ✅ | ✅ | ✅ |
| Fuzz | libFuzzer (Linux, L0 modules) | Parsers never crash | 60 s/target | 1 h/target | 1 h/target |
| Stress | XCTest | 500 tabs, 50 Spaces, rapid switching | smoke | full | full |
| Performance | XCTest metrics on the fixed VM | [Budgets](performance-budget.md) | launch + size | full + trend | full |
| Upgrade | previous release → HEAD | Data survives app updates | — | ✅ | ✅ |
| Reproducibility | double build + compare | Unsigned outputs are identical | — | ✅ | ✅ |

## Coverage policy

| Scope | Floor | Why |
|---|---|---|
| L0 pure modules (BrowserCore, SecurityPolicy, Storage, Networking) and Import | **≥ 95% lines** | Pure logic; there's no excuse for untested branches |
| Engine adapters (WebKitEngine, ChromiumEngine) | ≥ 80% lines | Some paths need real crashes or OS events |
| UI modules | no line floor | Proven by UI and snapshot tests; a line % on SwiftUI just gets gamed |
| Everything | **no-decrease ratchet** versus `main` | Coverage only goes up |

## Rules

1. **No network in automated tests.** Use `data:` URLs, fixtures, and `LocalTestServer` (loopback HTTPS with a test CA).
2. **No real user data.** UI tests run with `NERA_UI_TEST=1` (in-memory library). Fixtures are synthetic.
3. **Deterministic.** Inject the clock and UUIDs. No fixed sleeps; poll with a timeout (see `storeDebouncesAndFlushes`).
4. **Both engines.** A test of engine behavior goes in the conformance kit, not in one adapter's tests.
5. **Every bug fix ships with a test that fails before the fix.**
6. New `Action` → reducer test. New security rule → policy test + conformance test. New parser → fuzzer.
7. Checklist evidence cites real test names. The validator fails if a test is renamed without updating the checklist.

Run locally: `make test-unit` (fast loop), `make smoke` (full PR gate).

## Inventory

| Target | Tests |
|---|---|
| BrowserCoreTests | 27 (reducers, omnibox) |
| SecurityPolicyTests | 18 (navigation policy, origins, dialog throttle) |
| PageLifecycleTests | 16 (engine selection, memory, crashes, requests, default-deny) |
| WebKitEngineTests | 8 (16 conformance cases on real WebKit + adapter internals) |
| StorageTests | 6 (persistence, debounce, **migration from the 0.1 format**) |
| ImportTests | 6 · EngineKitTests 5 (`Decision` default-deny) · DownloadsTests 4 · ChromiumEngineTests 3 |
| macOS UI (XCUITest) | 5 (launch, open/close/restore, pin, `javascript:` blocked, **dialogs**) |

98 test functions; the conformance suite runs its 16 cases on every engine. Categories still to build are tracked as open items in the checklists.
