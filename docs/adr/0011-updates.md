# ADR-0011: Updates — Nera's own verified update check, Sparkle-compatible feed

**Status:** Accepted · **Date:** 2026-10-27 · **Related:** [ADR-0006](0006-engine-strategy-v2.md), [release pipeline](../release-pipeline.md)

## Context

The plan named Sparkle 2 for updates. Nera so far ships no third-party packages: CEF is the only third-party
component, and every new one needs an ADR, a license review and a supply-chain review (AP-6). Sparkle's job has
two parts:
- **Deciding and trusting:** reading the feed, picking the right release for this install, and checking its
  EdDSA signature. This is small, security-critical logic.
- **Installing:** replacing a running, signed app bundle, with an XPC installer and authorization prompts.

Sparkle is mature at installing. Without a Developer ID, though, no build can be installed over another one on
users' Macs, so the installer can't be exercised yet.

## Decision

1. **Feed format: Sparkle 2's appcast.** This covers `sparkle:version`, `shortVersionString`, `channel`,
   `minimumSystemVersion`, `phasedRolloutInterval`, `criticalUpdate` and the `enclosure` `edSignature`.
   Nera's feeds can therefore be handed to Sparkle unchanged.
2. **Deciding and trusting are Nera's own code,** in the `Update` module (L2, Foundation + CryptoKit):
   - `Appcast` parses the feed. External entities are never resolved. Unsigned, non-HTTPS and unknown-channel
     items are dropped.
   - `UpdatePolicy` picks the release: it handles the channel (stable ⊂ beta ⊂ nightly), the minimum macOS
     version and the staged rollout (7 groups, one per interval; critical updates skip the rollout).
   - `UpdateVerifier` checks the exact length and the Ed25519 signature against the public key built into the
     app.
   - `UpdateChecker` fetches only through `NeraHTTPClient`, so the feed host must be on the network allowlist
     and in the inventory.
3. **Signing tools use CryptoKit too:** `scripts/release/sign-update.swift` (same key format as Sparkle's
   `generate_keys` and `sign_update`) and `scripts/release/make-appcast.py`. A fixture test keeps the script's
   output and the parser in step.
4. **Installing is decided when the Developer ID exists (REL-015).** The default is to adopt Sparkle 2's
   installer at that point (ADR amendment + dependency register entry), feeding it the verified file.
   Until then, an update is offered as a verified download the user opens.

## Consequences

- The trust decision is ours, small and fully unit-tested (wrong key, tampered byte, wrong length, rollout
  timing, XXE), with no new dependency today.
- Switching to Sparkle later changes no feed, key or release step.
- The feed host isn't chosen yet. `NetworkAllowlist.nera` stays empty, so the checker can't reach anything until
  the host is added to the allowlist and the inventory together.

## Amendment (2026-11-04): installing

With the Developer ID in place (REL-015), installing is Nera's own small step instead of Sparkle's installer, so
no third-party code joins the update path and every request still goes through `NeraHTTPClient` and its
allowlist (SEC-063):

1. **Feed and key.** The feed is `appcast.xml` on the public repo's latest GitHub release
   (`NeraUpdateFeedURL` in Info.plist); GitHub redirects downloads to `release-assets.githubusercontent.com` or
   `objects.githubusercontent.com`, both allowlisted and in the network inventory. The Ed25519 public key is
   `NeraUpdatePublicKey`; the private key lives only in the maintainer's Keychain ("Nera Update Signing Key").
   `scripts/release/make-dmg.sh` signs each DMG with it and writes `appcast.xml`.
2. **Two independent gates.** `UpdateChecker` accepts the download only with the exact length and a valid Ed25519
   signature. `UpdateInstaller` then mounts the image read-only and requires the app inside to pass a deep, strict
   code-signature check against `anchor apple generic and identifier "<bundle ID>" and certificate
   leaf[subject.OU] = "<the running app's team>"`, and to be the announced build. Builds without a Developer ID
   team have no installer and only point at the release page.
3. **Staging and swap.** The verified app is copied next to the running one (`.Nera-update.app`, same folder, so
   the swap is a rename) and checked again. When Nera quits (or at "Restart to Update"), a short shell script,
   given the paths as arguments, waits for Nera's process to exit, swaps the bundles, restores the old one if the
   swap fails, and reopens Nera when asked. A folder Nera can't write to falls back to offering the download.
4. **Rollout.** `UpdatePolicy` still applies the channel, minimum macOS and staged rollout before anything
   downloads.

Sparkle stays a drop-in option: the feed and key format are unchanged.
