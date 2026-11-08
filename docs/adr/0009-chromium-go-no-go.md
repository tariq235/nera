# ADR-0009: Chromium (CEF) go/no-go after the CEF prototype

**Status:** Accepted (2026-10-26, by the maintainer; decision 2 finalized by the Chrome-style hosting study the same day) · **Date:** 2026-10-26 · **Amends:** [ADR-0006](0006-engine-strategy-v2.md)

## Context

ADR-0006 made Chromium (via CEF) the macOS default engine and left five questions for a prototype. The CEF prototype answered them with a working prototype on CEF 156.0.14 / Chromium 156.0.8078.48: a SwiftUI app, an ObjC++ bridge, a Chromium adapter on the unchanged engine contract, and measurements against WebKit.

The deciding finding: CEF has no extension API of its own any more. Extensions run only in **Chrome-style** browsers. A browser placed inside an app-provided `NSView` is always **Alloy** style. Embedded Alloy browsers run MV3 extensions (service workers, `declarativeNetRequest` blocking, content scripts, messaging, `scripting`), but Chrome's tab model doesn't know them, so `chrome.tabs` / `chrome.windows` see nothing. Chrome-style browsers have the full API, but CEF hosts them in **CEF Views windows**, so Nera's SwiftUI has to live inside that window instead of the reverse.

## Decision

1. **GO: Chromium via CEF stays the macOS default engine.** The engine contract fits Chromium unchanged: the spike adapter passes all 16 conformance cases that WebKit passes. Startup (0.39 s vs 0.33 s to first load), frame pacing and main-thread behavior are on par with WebKit. Sandboxing, the Hardened Runtime and library validation hold with no exceptions.
2. **Hosting model: embedded (Alloy) — final after the Chrome-style hosting study.** `ChromiumEngine` hosts each page as a Chromium view inside Nera's own SwiftUI window, exactly as the prototype's adapter that passed all 16 conformance cases. the Chrome-style hosting study showed that the Chrome-style model can't reach full extension compatibility with native UI on standard CEF:
   - Stock CEF allows **one Chrome-style browser view per window** ("Cannot add multiple Chrome style BrowserViews"), so tabs can't share a Chrome-style window.
   - In a Chrome-style window, Chromium's content view claims all clicks, so SwiftUI only works with a patch of a private Chromium class.
   - CEF has **no API for extension toolbar actions** (icons, badges, popups) in either model.
   - The workable Chrome-style variant (native Nera window + one child CEF window per tab) passed every automated native-feel check and gives extensions `chrome.tabs`. It still lacks toolbar actions, and it needs two runtime adjustments to CEF's window class.
   - Per the maintainer's rule ("otherwise fall back to the embedded approach with reduced extension capabilities"), embedded is the default.
   - **Extension support in the embedded model:** MV3 service workers, `declarativeNetRequest` blocking (uBlock Origin Lite verified), content scripts, `scripting` and messaging. Not available: `chrome.tabs`/`windows`, extension toolbar actions.
   - **Tracked follow-ups, not blockers:**
     - ENG-030: tabs/windows coverage via per-tab Chrome-style windows behind the same adapter.
     - ENG-031: toolbar actions, Web Store install and 1Password pairing via a custom CEF build.
     - ENG-032: the custom CEF build pipeline, shared with proprietary codecs.
   - Each follow-up gets its own ADR before it lands.
3. **Engine independence is unchanged.** CEF stays behind `ChromiumEngine` (ObjC++ bridge, no CEF types in Swift). If a later hosting model (per-tab windows) is adopted, it stays an adapter concern behind `WebPage.view`. No feature module may know which hosting model is in use.
4. **Security amendments to ADR-0006:**
   - **Only the Renderer helper holds `com.apple.security.cs.allow-jit`.** The GPU helper was measured to work without it (WebGL2 and WebGPU verified). All other bundles, including the main app, have no entitlements.
   - **ChromiumEngine must set its own Keychain item** (`CefSettings.keychain_service_name`/`keychain_account_name`). The default "Chromium Safe Storage" item is shared with every other CEF/Chromium app, and makes the first network request block on a Keychain prompt.
   - Library validation stays on. No `disable-library-validation`.
5. **Media:** ship the standard CEF build first. Route sites that need H.264/AAC or DRM to the WebKit fallback (FairPlay and H.264 verified in our macOS WKWebView) until both of these are done: patent licensing for a `proprietary_codecs` build, and a Widevine license with VMP signing.
6. **Budgets for the Chromium macOS build** (enforced in CI when ChromiumEngine ships):

   | Budget | Limit |
   |---|---|
   | Download (zip/dmg) | ≤ 160 MB |
   | App bundle | ≤ 360 MB |
   | First load | ≤ 0.5 s |
   | Idle memory, one tab, no extensions | ≤ 700 MB |
   | Idle CPU | ≤ 1.5 % |
   | Main-thread lateness p99 | ≤ 10 ms |

## Consequences

- Browser features start on the real Nera codebase. Chromium lands in `ChromiumEngine` behind EngineKit (embedded hosting). No more prototype apps unless a new architectural question needs one.
- Users get working content blockers (uBlock Origin Lite) and content-script extensions first. Password-manager popups that act on "the current tab", extension toolbar buttons and Web Store installs come with the follow-ups.
- Size and memory grow sharply versus WebKit (147 MB download, about 640 MB idle). That's accepted, mitigated by tab discarding and the budgets above.
- A custom CEF build (ENG-032) is the long-term route to full extension parity and H.264/AAC. Its cost (build pipeline, patch upkeep at every rebase) needs its own ADR.
- Checklist rows: own Keychain item (SEC-073), Renderer-only JIT (SEC-074), follow-ups ENG-030–ENG-032.
