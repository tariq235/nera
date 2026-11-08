# Passkeys and passwords (FEAT-027)

Nera never stores passwords itself (SR-032). Passkeys and passwords come from the system and from the
password managers people already use.

## Passkeys

| Engine | How | Needs |
|---|---|---|
| **WebKit** | WKWebView's built-in WebAuthn, using the system passkey UI and iCloud Keychain | `com.apple.developer.web-browser.public-key-credential` |
| **Chromium** | Nera's WebAuthn bridge (below) → Apple's browser passkey API (`ASAuthorizationPlatformPublicKeyCredentialProvider` / `…SecurityKey…` with `ASPublicKeyCredentialClientData`) | the same entitlement; macOS 14.4+ |

Without the entitlement, Chromium pages don't see `PublicKeyCredential`, so sites show their password sign-in.
Any WebAuthn call still gets `NotAllowedError` at once. Before the bridge, embedded Chromium hung forever on
WebAuthn (found by a probe on 2026-10-27).

### The Chromium bridge

```
page JS ── navigator.credentials.create/get ──► shim (renderer, installed before page scripts)
                                                  │  private `bridge(kind, json)`; the page can't reach it
                                                  ▼
                       renderer ── "nera.webauthn" process message ──► browser process (NRAChromiumPage)
                                                  │  origin = the FRAME's URL as Chromium knows it
                                                  ▼
             ChromiumPage checks ──► WebAuthenticator (SystemPasskeyAuthenticator) ──► system passkey UI
```

**Rules enforced before the system is asked:**
- **Origin from the browser process, never from the page.** A page can only ask for passkeys for itself.
- **Secure origins only:** HTTPS, or loopback for development. Others get `SecurityError`.
- **Cross-origin iframes are refused** (`NotAllowedError`). Native Chromium would require
  `allow="publickey-credentials-*"`, which the bridge can't see, so it takes the conservative choice.
- **Relying-party ID:** must be the page's host or a parent domain, never a public suffix (built-in list of
  common multi-label suffixes, single labels refused) and never an IP's parent (`WebAuthnOptions.relyingParty`).
  The system authenticator validates as well.
- **Untrusted page options:** size-capped, required fields checked, challenge ≥ 16 bytes.
- **One request at a time.** A cancel and a refusal both look like `NotAllowedError` to the page (privacy).

**Shim details** (`Apps/macOS/ChromiumHelper/webauthn_shim.h`, compiled into the renderer helper):
- Installed in every script context from `OnContextCreated`.
- `PublicKeyCredential` (with `isUserVerifyingPlatformAuthenticatorAvailable`, `getClientCapabilities` and
  `parse…FromJSON`) is defined only when an authenticator is available. The flag comes from the browser at
  browser creation (`extra_info`).
- Blink installs its native `PublicKeyCredential` after context creation, so the shim patches on the first DOM
  insertion. That's a MutationObserver callback, which the parser runs before any page script.
- Conditional (autofill) passkey UI isn't offered yet.

**Tests:**
- Conformance P01: the full path in real Chromium, with the frame's origin checked.
- Conformance P02: a refusal arrives as `NotAllowedError` and never hangs.
- `ChromiumWebAuthnBridgeTests`: insecure, file, cross-origin and unknown requests never reach the
  authenticator; no authenticator means fail fast and no `PublicKeyCredential`.
- `WebAuthnOptionsTests`: relying-party rules, parsing, hostile input.

### Turning it on (after Apple grants the managed capability)

1. Apple approves the request at <https://developer.apple.com/contact/request/macos-browsers-passkeys/>. It's
   submitted by the Account Holder, and the form mentions organization accounts.
2. Enable the capability on the `dev.nera.browser` App ID and create a **Developer ID** provisioning profile.
   Both steps can go through the App Store Connect API.
3. Release build: `NERA_PASSKEYS_ENTITLED=YES` and `CODE_SIGN_ENTITLEMENTS=Apps/macOS/Nera-Passkeys.entitlements`
   with the profile embedded. The Info.plist flag `NeraPasskeysEntitled` then switches the authenticator on.
   The entitlement gate already allows the key.

## Passwords

There's no system API for a third-party browser to fill iCloud Keychain passwords into web pages. Apple's
supported route is its **iCloud Passwords** extension, which talks to the system Passwords helper over native
messaging. Nera supports that route, and the same one for desktop password managers:
- The Extension Manager installs iCloud Passwords (`pejdijmoenmkgeppbflobdenhhabjlaj`), 1Password or Bitwarden
  from the Chrome Web Store, with verified signatures.
- At Chromium start, Nera mirrors the native-messaging manifests of an **allowlist** of hosts into its
  Chromium data folder: `com.apple.passwordmanager`, `com.1password.1password`, `com.8bit.bitwarden`. A manifest
  is mirrored only if it names itself, uses stdio, points at an existing executable, and allows specific
  extension IDs (no wildcards). See `NativeMessagingHosts`.

**Status (2026-10-27):**
- iCloud Passwords installs from the store, and Apple's host manifest is mirrored.
- Whether Apple's helper accepts connections from Nera still needs an interactive check: it needs the unlocked
  screen and Passwords' verification code. The helper may limit which browsers can connect.
- Filling from an extension *popup* is limited in embedded Chromium (ADR-0012); in-page autofill works.
