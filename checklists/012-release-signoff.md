# 012 — Release Signoff (template)

<!-- checklist: template -->

Copy to `docs/releases/v<version>.md`, tick every box, and get two maintainer signatures before the stable tag. Requirements: [release requirements](../docs/standards/release-requirements.md).

## Gates

- [ ] **SIGN-001** All required CI checks green on the release commit — P0 · owner: nera · evidence: —
- [ ] **SIGN-002** Nightly tier green for the last 3 nights (fuzz, stress, performance, upgrade, reproducibility) — P0 · owner: nera · evidence: —
- [ ] **SIGN-003** `check-checklists.py` passes; no P0 regressions since the last release — P0 · owner: nera · evidence: —
- [ ] **SIGN-004** Chromium version within SLA (no unshipped security release older than 7 days) — P0 · owner: maintainer · evidence: —
- [ ] **SIGN-005** Upgrade test from the previous stable keeps all user data — P0 · owner: nera · evidence: —
- [ ] **SIGN-006** Notarized, stapled, Gatekeeper-verified on a clean machine — P0 · owner: nera · evidence: —
- [ ] **SIGN-007** Sparkle appcast signed; staged rollout percentage set — P0 · owner: nera · evidence: —
- [ ] **SIGN-008** SBOM, checksums and provenance attached — P0 · owner: nera · evidence: —
- [ ] **SIGN-009** Release notes include security fixes (CVE IDs) and the Chromium version — P0 · owner: maintainer · evidence: —
- [ ] **SIGN-010** Safe Browsing / Web Risk licensing still valid for the distribution model — P0 · owner: maintainer · evidence: —
- [ ] **SIGN-011** Manual exploratory pass (30 min) on macOS + iPad + iPhone — P1 · owner: maintainer · evidence: —

## Signatures

| Role | Name | Date |
|---|---|---|
| Release manager | | |
