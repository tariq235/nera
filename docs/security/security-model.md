# Security model

A browser is the most attacked app on a computer. Our bar: **at least as safe as Safari and Chrome, and private by default**.

This page is the hub. Each fact lives in exactly one place:

| Question | Where |
|---|---|
| What are we protecting, from whom, and where are the trust boundaries? | [Threat model](threat-model.md) |
| What rules must the code follow? | [Security requirements `SR-xxx`](../standards/security-requirements.md) |
| Which rules are proven today, and by which test? | [Checklist 000 Browser Security](../../checklists/000-browser-security.md), [002 Privacy](../../checklists/002-privacy.md) |
| Why is the macOS app not App-Sandboxed? | [ADR-0006](../adr/0006-engine-strategy-v2.md#security-profile-on-macos-precise-statement) |
| How do I report a vulnerability? | [SECURITY.md](../../SECURITY.md) |

## Layers of defense

1. **Web content is always untrusted and always in an engine sandbox**: WebKit WebContent processes, and Chromium renderer/GPU processes under seatbelt with site isolation.
2. **One engine-neutral navigation policy** (`NavigationPolicy`) runs before either engine sees a URL: HTTPS-Only, `javascript:`/`data:`/`file:` rules, credential-URL blocking, confirmation for external apps.
3. **Default-deny requests** from the engine: permissions, downloads, dialogs, file pickers, auth and cert errors (engine contract v2).
4. **Hardened binaries**: hardened runtime and library validation everywhere, a per-bundle entitlement allowlist, forbidden Chromium switches. App Sandbox on iOS; on macOS the main app runs without it because Chromium's browser process needs what it denies (ADR-0006), and all web content runs in the engines' sandboxes.
5. **Private by construction**: zero third-party SDKs, a network inventory enforced in CI and at runtime, redacted logs.
6. **Supply chain**: pinned and hashed inputs (CEF), secrets and dependency scanning, GitHub-hosted CI runners (no secrets for forks), signed and notarized releases, EdDSA updates, maintainer-approved releases.
7. **Patch speed**: Chromium security releases shipped in ≤ 7 days (≤ 48 h if exploited).

## Entitlements by build

| Build | App Sandbox | Main app entitlements | Helpers |
|---|---|---|---|
| **macOS** (Chromium bundled; WebKit fallback) | ❌ off (ADR-0006) | Hardened runtime, library validation; `device.camera`, `device.audio-input`, `personal-information.location` (+ `get-task-allow` in Debug only) | Renderer: `cs.allow-jit` only (V8 needs it). GPU, network/storage utilities, plugin, alerts: none. CEF framework: none |
| iOS / iPadOS | ✅ always | Default iOS sandbox; later `com.apple.developer.web-browser` (Apple approval) | — |

**Forbidden in every bundle** without an ADR: `cs.disable-library-validation`, `cs.allow-unsigned-executable-memory`, `cs.disable-executable-page-protection`, `cs.allow-dyld-environment-variables`. Enforced per bundle (app, five helpers, CEF framework) by `scripts/ci/check-entitlements.sh`, which also requires the hardened runtime on every bundle and `codesign --verify --deep --strict`.

## Network inventory

Every host the app contacts **on its own** (not sites the user visits) must be listed here. CI enforces this for Swift sources and for the runtime allowlist (`NetworkAllowlist.nera`); at runtime `NeraHTTPClient` refuses any other host, including on redirects, before connecting, and the architecture check forbids networking APIs anywhere else (SEC-063), and a clean-profile packet capture checks the Chromium engine's background traffic.

| Host | Purpose | When |
|---|---|---|
| `duckduckgo.com` | Default search engine (query URL only, sent only when the user searches) | User searches |
| `www.google.com` | Optional search engine | User picked Google and searches |
| `www.bing.com`, `search.brave.com`, `www.ecosia.org`, `kagi.com`, `www.startpage.com`, `www.perplexity.ai`, `chatgpt.com`, `search.yahoo.com` | Optional search engines (Settings › General › Search engine); query URL only | User picked one and searches |
| `api.github.com` | Update check for builds without an update key (development builds): the latest release of `tariq235/nera` (version number only). At most once a day; off in Settings › General | Launch |
| `github.com`, `release-assets.githubusercontent.com`, `objects.githubusercontent.com` | Updates (ADR-0011): the signed feed `releases/latest/download/appcast.xml` of `tariq235/nera`, then the new version's disk image it names (GitHub redirects downloads to its asset hosts). Nothing about the user is sent. At most once a day; off in Settings › General | Launch |
| `safebrowsing.googleapis.com` | Phishing and malware protection (Google Safe Browsing v5, Local List mode). Threat lists of 4-byte hash prefixes are downloaded and updated on Google's schedule (about every 30 minutes; ~4 MB the first time). Only when a page's address matches a local prefix are those **4-byte prefixes** sent to look up the full hashes; the address itself never leaves the Mac. Google sees the Mac's IP address and Nera's API key on these requests. Chromium pages only (WebKit uses Apple's built-in warning). Off in Settings › Privacy | Launch, then on Google's schedule; a page matching a local prefix |
| `developers.google.com`, `support.google.com` | Links on the Safe Browsing warning ("Advisory provided by Google", "Learn more"), required by Google's usage guidelines. Opened as ordinary pages only when the user clicks one (a site visit) | User clicks a link on a warning |
| `clients2.google.com` | Chrome Web Store extension download (Google's update service; CRX3 verified against the developer and Web Store keys before unpacking) | User installs an extension |
| `clients2.googleusercontent.com` | Download redirect target of the above | User installs an extension |
| `chromewebstore.google.com` | Opened as an ordinary tab by Settings › Extensions › Open Chrome Web Store (a site visit, not a request of Nera's own) | User clicks the button |
| *the visited site's own host* | Favicon fetch by the WebKit engine (no cookies, 512 KB cap; Chromium fetches icons with the page) | A page finishes loading |
| `www.youtube.com`, `github.com`, `mail.google.com`, `www.notion.so`, `www.figma.com`, `open.spotify.com`, `chatgpt.com`, `claude.ai`, `www.wikipedia.org`, `www.reddit.com`, `www.linkedin.com`, `x.com` | Suggested Favorites in the welcome screen's Start fresh step. Only the addresses the user picks are stored; nothing is contacted until the user opens one (a site visit) | User opens a Favorite |
| `clients2.google.com` (uBlock Origin Lite, ID `ddkjiahejlhfcafbddmgiahcphecmpfh`) | Welcome screen's "Block ads and trackers", and extensions picked for import: installed through the Web Store path above | User leaves the option ticked |

**Chromium's own background traffic** (`Apps/macOS/Chromium/NRAChromium.mm`): switches `--disable-background-networking`, `--disable-component-update`, `--disable-domain-reliability`, `--disable-sync`, `--no-pings`, `--disable-client-side-phishing-detection`, `--metrics-recording-only`; preferences set at start: network time queries off, component updates off, Chromium's own DNS-over-HTTPS off (names resolve through macOS, so the Mac's DNS settings and filters apply), Translate and Google AI features off per profile.

**Audit** (`scripts/privacy/chromium-traffic.sh`: a Debug Nera on a clean throwaway profile with Chromium's net log, 60 s idle, then 60 s with one page open; every host Chromium contacted is listed). Results on 2026-11-04 (CEF 156.0.14 / Chromium 156.0.8078.48):

| Host | Request | Status |
|---|---|---|
| `clients2.google.com/time/…` | Network time | **Stopped** (preference) |
| `edgedl.me.gvt1.com` | Component download | **Stopped** (preference) |
| `doh.opendns.com` (the Mac's own resolver) | DNS over HTTPS | **Stopped** (resolves through macOS) |
| `update.googleapis.com/service/update2/json` | Component update check (one on-demand component), about every 30 s at startup | **Still sent**: no app data, but it reaches Google |
| `www.google.com/async/folae` | Google AI features eligibility | **Still sent** |
| `www.gstatic.com/…/translate_ranker_model…` | Translate model, when a page is open | **Still sent** |

The three remaining requests come from Chromium services that ignore the switches and preferences above and bypass CEF's request handlers. Removing them needs either a CEF build with those services compiled out or Chromium's managed-policy mechanism (`chrome_policy_id`). Tracked by PRV-005/PRV-006; Nera doesn't claim "no background requests" until the audit shows none.

Planned rows (added when the code lands): CloudKit (Apple).

## Web-security conformance

The same suite runs on Chromium and WebKit on every PR (WebKit in `swift test`, Chromium in the app's Debug
self-test), against `LocalTestServer`: loopback-only HTTP + HTTPS with a throwaway test CA and expired,
wrong-host and self-signed certificates generated per run. Cases S01–S14 (parity matrix in
[checklist 005](../../checklists/005-browser-engine.md#conformance-matrix)): certificate failures, valid TLS,
mixed content, CSP, nosniff, SameSite=Lax, popups without a gesture, redirects to `file:`, profile isolation
(cookies, storage, cache) and private sessions (nothing shared, nothing on disk).

Test-only trust: in Debug test runs WebKit adds the test CA as an *extra* anchor (full validation still runs)
and Chromium allow-lists only the valid test certificate's public key. Neither hook exists in Release builds;
the Chromium switches involved are stripped there.

Known engine differences (documented, not hidden):
- Chromium treats `http://127.0.0.1` as potentially trustworthy, so loopback HTTP on an HTTPS page isn't
  "mixed" there; S05 uses a non-loopback test name for Chromium (Debug-only resolver rule).
- Cookies without a SameSite attribute: Lax in Chromium, not in WebKit (SEC-023 open).
- HSTS can't be exercised locally (engines ignore it for IP addresses, Chromium also for localhost); it's
  engine behavior verified by the vendors.

The suite found and fixed a real Chromium bug: every persistent profile had silently fallen back to in-memory
storage because CEF compares profile paths with the *resolved* root path (`/var` → `/private/var`).

## Sites in the other engine

Video and streaming sites, and sites the user picks, open with WebKit. When a tab's navigation needs the other
engine, the navigation policy blocks it in the current engine *before any request* and Nera loads it once in the
other engine. The site's cookies (its registrable domain only) are copied between the two engines' stores **of the
same profile or private session**; nothing crosses profiles, nothing leaves the Mac, and private-session cookies
stay in memory. Popups never move, so they keep their opener.

## Nera's scripts in pages

Nera runs a few scripts of its own in pages; none sends anything off the Mac.

- **Media watcher** (`MediaWatch`, every frame, before the page's scripts): tells Nera whether the frame plays
  sound, for the tab's speaker, Mute, the mini player and Picture in Picture. In WebKit it runs in Nera's isolated
  script world; in Chromium the renderer helper installs it (`Apps/macOS/ChromiumHelper/media_watch.h`) with a
  private `report` function only the watcher's closure holds. Its only output is "playing sound: yes/no", which
  changes nothing but that tab's own state, so a page faking it can only mislabel itself.
- **Picture in Picture** (when you leave a tab playing a video with sound): floats the page's largest such video,
  run as a click; coming back puts it back. Off in Settings › General.
- **Passkeys** ([passkeys.md](passkeys.md)), **SiteStyles** and the **mini player** (play/pause).

## Security roadmap

Open P0 rows are tracked in checklist 000. Before public beta: an external security review (TM-007). After 1.0: a public bug bounty and yearly audits.
