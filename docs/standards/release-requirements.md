# Release requirements

Pipeline mechanics: [release pipeline](../release-pipeline.md). Capability status: [checklist 001](../../checklists/001-release-pipeline.md). Per-release signoff: [template 012](../../checklists/012-release-signoff.md).

## Versions & channels

- SemVer `MAJOR.MINOR.PATCH`. The Chromium version is shown in About and in the release notes.
- **Nightly** (every green `main`) → **Beta** (weekly) → **Stable** (every ~4 weeks, aligned with Chromium stable).
- Stable releases go out by staged rollout: 10% → 50% → 100% over 72 h, paused automatically on a crash-rate spike (opt-in MetricKit).

## A release MUST

1. Come from a tagged commit on `main` with every required check green.
2. Pass the nightly tier for 3 consecutive nights (fuzz, stress, performance, upgrade, reproducibility).
3. Have every P0 item in checklists 000, 001, 002, 005 and 007 ticked, or carry an explicit, dated waiver signed by two maintainers.
4. Be Developer ID signed, notarized and stapled (macOS), and signed by Sparkle EdDSA.
5. Ship an SBOM, SHA-256 checksums and a provenance attestation.
6. Include `THIRD_PARTY_NOTICES` (Chromium/CEF and all dependencies).
7. Be approved by two maintainers in the `release` environment.

## Security releases

- Chromium security fixes: shipped within **7 days**, or **48 hours** if exploited in the wild ([checklist 006](../../checklists/006-chromium-upgrade.md)).
- Nera vulnerabilities: timelines in [SECURITY.md](../../SECURITY.md).
- Emergency path: a patch branch from the last stable tag, then the full PR gate, then a reduced nightly (security + conformance + upgrade), then stable with the Sparkle critical-update flag.

## Rollback

Sparkle can't downgrade automatically. Rollback means shipping vN+1 with the fix. So **schema migrations must stay readable by the previous version for one release** (additive changes only), or ship behind a flag.
