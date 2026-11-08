# Emergency security release (REL-013)

Target: **a fix on users' Macs within 24 hours** of deciding to ship, for an exploited Chromium or WebKit bug, or
a critical Nera bug.

| Step | Who | Time |
|---|---|---|
| 1. Open a private security advisory (GitHub → Security → Advisories) and a private fork for the fix | maintainer | 0:00 |
| 2. Fix it. For Chromium: bump CEF in `scripts/engine/fetch-cef.sh` (version + SHA-256) and `dependencies.json`, then `make project` | engineer | ≤ 6 h |
| 3. Locally: `make smoke` and `make conformance` (both engines) | engineer | ≤ 1 h |
| 4. Merge the PR. Normal CI gates apply; size growth from a CEF bump is approved with the label | maintainer | ≤ 1 h |
| 5. Tag `vX.Y.Z` (signed tag). `release.yml` builds, signs, notarizes, signs the update, and writes the SBOM + appcast | CI + maintainer approval | ≤ 1.5 h |
| 6. Publish the appcast entry with `--critical` (skips the staged rollout) and publish the advisory | maintainer | ≤ 30 min |
| 7. Verify: an older installed build is offered the update; `sign-update.swift verify` passes on the published DMG | maintainer | ≤ 30 min |

## A bad update (pull it first, then fix forward)

1. `python3 -I scripts/release/make-appcast.py --feed appcast.xml --remove <bad build>` and upload the feed: no Mac is
   offered that build any more (about a minute).
2. Ship the fix with a higher build number through the steps above. Macs that installed the bad build update to it.

## Rules

- **Never weaken a gate to ship faster.** Gates that only fail on size, or on known-flaky UI tests, follow the
  normal note-and-merge rule.
- **Critical updates skip the rollout,** but never the signature, notarization or entitlement checks.
- **Keep the fix private** (private fork, embargo) until step 6.

## Rehearsal

Rehearse once per quarter with a dry run:

1. `gh workflow run release.yml -f version=0.0.0-drill.N -f channel=beta -f dry_run=true`
2. Time steps 2–5 on a trivial CEF patch bump.

Record the date and the duration below.

| Date | Duration | Notes |
|---|---|---|
| 2026-11-04 | ~1 s + upload | Pull drill on a copy of the build 9 feed (`make-appcast.py --remove`): pulled, re-run refused. Full release drill (steps 2–7) still pending |
