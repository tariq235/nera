# ADR-0005: License — MPL-2.0 for everything, DCO for contributions

**Status:** Accepted · **Date:** 2026-11-05 · **History:** Apache-2.0 before the first public release.

## Context

A browser handles people's passwords, banking and everything they read. An independent developer can only earn
that trust if anyone can read, build and audit all of it. Every comparable browser people trust is open source
(Firefox, Brave, Ladybird); the closed ones are backed by established companies.

## Options

| License | Fit |
|---|---|
| **MPL-2.0** (Firefox, Brave) | File-level copyleft: improvements to our files stay open, while the code can be combined with other licenses. Compatible with Chromium's BSD and our Apache/MIT/BSD dependencies |
| Apache-2.0 / MIT | Permissive: a fork could take our security work closed |
| GPL-3.0 | Strong copyleft across the whole program; awkward with App Store distribution and some dependencies |

## Decision

- **Everything is MPL-2.0** (`LICENSE` is the license text). Every published source file carries the MPL-2.0 header;
  `scripts/ci/check-mpl-headers.py` enforces it in CI.
- **Copyright holder:** Tariq Mohammad.
- **Contributions:** Developer Certificate of Origin sign-off (`git commit -s`), no CLA; contributions are MPL-2.0.
- **Source availability (MPL §3.2):** the app's About section and the DMG notes point to the public repository
  (`NeraSourceURL`); the release workflow refuses to publish while that address doesn't resolve.
- **Trademark:** the product name and logo are not licensed; forks must rebrand.
- **Third-party code:** listed in `THIRD_PARTY_NOTICES.md`; components shipped inside CEF (including LGPL ones) are
  covered by the CEF/Chromium notices. uBlock Origin Lite (GPL-3.0) is downloaded from the Chrome
  Web Store at runtime, never redistributed.
