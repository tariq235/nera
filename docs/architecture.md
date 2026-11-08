# Architecture

Principles: [architecture principles](standards/architecture-principles.md) · Engine decision: [ADR-0006](adr/0006-engine-strategy-v2.md) · Security: [security model](security/security-model.md) · Budgets: [performance budget](standards/performance-budget.md).

## Shape

```
            Nera UI (SwiftUI/AppKit) + feature modules
                           │   no engine imports (CI-enforced, AP-1)
                    EngineKit protocols + conformance kit
                 ┌─────────┴──────────┐
          ChromiumEngine          WebKitEngine
       (macOS default, CEF)   (iOS/iPadOS; macOS fallback)
```

One shared UI, one implementation of Spaces, sidebar, downloads, history, sync and intelligence. Only the rendering layer differs per platform.

## Module map

Package `Packages/NeraKit`. Each module is independently testable and has its own test target.

| Layer | Module | What it owns | Imports (enforced) |
|---|---|---|---|
| L4 Shell | `BrowserShell` | `AppModel` (coordinator), `RootView`, request prompts, menus, `WebViewHost` | all L0–L3 except engine adapters |
| L3 Feature UI | `Sidebar` · `CommandBar` | Views over `BrowserState` + a small host protocol (`SidebarHost`, `CommandBarHost`) | BrowserCore, SecurityPolicy, DesignSystem, SwiftUI |
| L3 | `DesignSystem` | Theme, site/Space icons, clipboard | BrowserCore, SecurityPolicy, SwiftUI |
| L2 Services | `PageLifecycle` | `PageManager`, `EngineRegistry`, memory pressure | BrowserCore, EngineKit, SecurityPolicy |
| L2 | `Import` | Arc importer (Chrome/Safari later) | BrowserCore |
| L2 | `Downloads` | `DownloadPlanner` (safe filenames, no overwrite) | Foundation |
| L1 Engine | `EngineKit` | The contract ([ADR-0008](adr/0008-engine-contract-v2.md)) | SecurityPolicy, Foundation, AppKit/UIKit (`PlatformView`) |
| L1 | `WebKitEngine` · `ChromiumEngine` | Adapters. **Imported only by the apps' composition root** | EngineKit, SecurityPolicy (+ WebKit / CEF) |
| L0 Foundation | `BrowserCore` | Models, actions, pure reducers (tabs, spaces, library), store, omnibox | Foundation, Observation |
| L0 | `SecurityPolicy` | `NavigationPolicy`, `SecurityOrigin`, `DialogThrottle`, `DisplayURL` | Foundation |
| L0 | `Storage` | `JSONFileStore` (atomic, versioned), `InMemoryStore` | BrowserCore |
| Test-only | `TestSupport` · `EngineConformance` | `TestEnv`, `FakeEngine`/`FakePage`; the shared engine suite | — never linked into apps |

**Created when they have code** (AP: no empty modules): `Permissions` (persisted per-origin decisions), `Networking` (runtime host allowlist), `Diagnostics`, `Update`, then `History`, `Bookmarks`, `Sync`, `Extensions`, `Settings`, `Intelligence` with their features.

Rules are enforced by `scripts/ci/check-architecture.py`: layering, engine independence (no `WK*`/`Cef*` or engine `#if` outside adapters), per-module framework allowlist, and forbidden APIs (trust overrides, sandbox-weakening switches).

## Data flow

```
 user / menu / page event
          │  Action
          ▼
   BrowserStore.send ──► Reducer.reduce(&state, action, env) ──► [Effect]
          │                                                      │
   SwiftUI re-renders (Observation)              PageManager.handle(effect)
          │                                                      │
   Storage.save (debounced, atomic)            WebPage.load / discard (any engine)
                                                                 │
                         engine event → WebPageDelegate → Action (.tabDidUpdate, …)
                         engine request → Decision<T> (default-deny) → UI prompt / policy
```

## Domain model

```
Profile ─┬─ favorites: [Tab]          (grid at top of sidebar, shared by the profile's Spaces)
         ├─ engine: .chromium | .webkit (per profile; Chromium default on macOS)
         └─ isolated website data store
Space ── icon, theme, profileID
      ├─ pinned: [Node]   (kept; ⌘W unloads)
      └─ today:  [Node]   (temporary; ⌘W archives; auto-archived after 12 h)
Node = tab(Tab) | folder(Folder: [Node]) | split(Split: [Tab])
Archive: closed/expired tabs (500 cap) · recentlyClosed: ⇧⌘T stack (50 cap)
```

## Engine contract v2

Designed against WebKit **and** CEF at the same time ([ADR-0008](adr/0008-engine-contract-v2.md), [API design](standards/api-design.md#engine-contract-rules-enginekit)):

| Area | WebKit mapping | CEF mapping |
|---|---|---|
| Page | `WKWebView` | `CefBrowser` + `CefClient` |
| Profile data | `WKWebsiteDataStore(forIdentifier:)` | `CefRequestContext` per profile (cache path per profile) |
| Navigation decision | `decidePolicyFor navigationAction` | `CefRequestHandler::OnBeforeBrowse` |
| New window | `createWebViewWith` | `CefLifeSpanHandler::OnBeforePopup` |
| JS dialogs | `WKUIDelegate` panels | `CefJSDialogHandler` |
| File chooser | `runOpenPanelWith` | `CefDialogHandler::OnFileDialog` |
| Downloads | `WKDownload` | `CefDownloadHandler` |
| Permissions | `requestMediaCapturePermissionFor` | `CefPermissionHandler` |
| Cert errors | `didReceive challenge` (default handling only) | `CefRequestHandler::OnCertificateError` |
| Crash | `webViewWebContentProcessDidTerminate` | `CefRequestHandler::OnRenderProcessTerminated` |
| Find / zoom | `find(_:configuration:)`, `pageZoom` | `CefBrowserHost::Find`, `SetZoomLevel` |

Every request crossing into the app carries a one-shot `Decision<T>` that **denies if it's dropped**.

## Swapping engines

```swift
// Apps/Shared/NeraApp.swift — the only file that names concrete engines
AppModel.live(engines: [ChromiumEngine(), WebKitEngine()])   // macOS
AppModel.live(engines: [WebKitEngine()])                     // iOS / iPadOS
```

`EngineRegistry` uses each profile's chosen engine if it's available, otherwise the first available one. Chromium is listed first. `ChromiumEngine` is a pure-Swift adapter that talks to CEF through the `ChromiumBackend` port; the macOS app supplies the CEF bridge ([ADR-0010](adr/0010-chromium-engine-structure.md)). Without a backend it reports `isAvailable == false`, so WebKit runs. When the app injects its CEF backend, Chromium takes over with no change to UI, store, reducers or services. Chromium is the macOS default; WebKit is the fallback (`NERA_ENGINE=webkit` or `defaults write <bundle id> NeraUseWebKit -bool YES`).
