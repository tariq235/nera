# ADR-0012: Chrome extensions on embedded Chromium — Extension Manager

**Status:** Accepted · **Date:** 2026-10-27 · **Builds on:** [ADR-0009](0009-chromium-go-no-go.md) (embedded hosting is final), [ADR-0010](0010-chromium-engine-structure.md)

## Context

Nera hosts Chromium pages inside its own SwiftUI window (Alloy style). The CEF prototype showed what Chrome's extension
system does there:
- **Works:** MV3 service workers, `declarativeNetRequest` blocking, content scripts, messaging and extension pages.
- **Doesn't work:** `chrome.tabs`/`windows` see no tabs, and CEF has no API for toolbar actions (icon, badge,
  popup with tab context).

CEF 156 has no extension-install API. Chromium loads unpacked extensions given with `--load-extension`, and only
into the profile it starts with.

The maintainer's direction: ship a polished Extension Manager for every extension that works today, and design it so a
future custom Chromium build can add toolbar-popup support without a redesign. Don't maintain a custom build
before public beta.

## Decision

1. **Packages are verified before anything touches disk** (`Extensions.CRX3`):
   - CRX3 only, and Manifest V3 only (current Chromium runs nothing else).
   - A valid signature by the developer key the extension ID is derived from.
   - For Web Store installs, also a valid signature by the Chrome Web Store publisher key. Its hash matches
     Chromium's `kPublisherKeyHash` and was checked against real store packages.
   - Unpacked with `ditto`; symlinks and paths that escape the folder are refused.
   - The developer key is written to the manifest's `key`, so Chromium keeps the store ID.
2. **Installs are user-initiated only:**
   - from a Chrome Web Store link or ID, downloaded through `NeraHTTPClient` (allowlisted hosts:
     `clients2.google.com`, `clients2.googleusercontent.com`), or
   - from a `.crx` file.
   The store's own "Add to Chrome" button doesn't work in an embedded browser; the manager says to paste the link.
3. **Storage:** `Application Support/<bundle>/Extensions/<id>/<version>/` plus `extensions.json`, holding the
   enabled flags and the extensions profile.
4. **Loading:** at Chromium start, the enabled folders go to `--load-extension`. Chromium's startup profile is
   pointed at the **extensions profile's** existing data folder, and that profile's pages use the global request
   context. So extensions run in exactly one Nera profile, chosen in Settings (default: the first profile). Other
   profiles and private windows run without extensions; Chrome also keeps them off in incognito by default.
   Changes apply after a relaunch (the manager offers Relaunch Now).
5. **Toolbar popups:** the sidebar's Extensions menu opens an extension's `default_popup` in a panel. Only these
   Nera-created pages may load `chrome-extension://` (`NavigationPolicy.allowsExtensionPages`); a web page or a
   typed URL can't. Requests from popups (dialogs, downloads, new windows) are declined.
6. **Honest limits in the UI:**
   - Every extension with access to all sites says so.
   - An extension whose popup uses `tabs`/`activeTab` gets "Popup actions on the current tab may not work yet".
   - An extension using `nativeMessaging` gets "Connecting to its desktop app may not work yet".

## The seam for a custom Chromium build (future, not before beta)

The UI talks to `ExtensionStore` (packages) and to the engine through `makeExtensionPopup`. A custom CEF build
that exposes Chrome's tab model and action API would add an **extension port** to `ChromiumBackend`, alongside
the existing page port:
- load and unload per profile at runtime (no relaunch);
- register Nera's tabs with Chrome's tab model (`chrome.tabs`, `activeTab`);
- action events (icon, title, badge) and "open the popup for tab X".

The sidebar button and popup panel stay as they are; they'd gain badges and tab context. Nothing in the
Extensions module, Settings or the store format changes.

## Consequences

- Content blockers (uBlock Origin Lite), page tools (Dark Reader) and content-script features of password
  managers work today in the extensions profile.
- Not yet:
  - password-manager popups that act on the current tab;
  - desktop-app pairing (1Password);
  - extensions in more than one profile;
  - automatic extension updates (P1: periodic check against Google's update service, same verification).
- Covered by conformance X01 (blocking and content scripts in a profile page) and X02 (popup page; ordinary pages
  can't reach extension pages), plus unit tests for verification, unpacking and the store.
