# 006 — Chromium Upgrade (template)

<!-- checklist: template -->

Copy to `docs/releases/chromium-<version>.md` for every CEF/Chromium bump and tick it there. SLA: ≤7 days after each CEF stable security release, ≤48 h for exploited-in-the-wild fixes ([ADR-0006](../docs/adr/0006-engine-strategy-v2.md)).

- [ ] **CHU-001** Read Chromium stable release notes + CEF changelog; list security fixes and breaking API changes — P0 · owner: maintainer · evidence: —
- [ ] **CHU-002** Bump pinned version + SHA-256 in `scripts/engine/fetch-cef.sh` — P0 · owner: nera · evidence: —
- [ ] **CHU-003** Rebuild `libcef_dll_wrapper`; fix bridge compile errors — P0 · owner: nera · evidence: —
- [ ] **CHU-004** Engine conformance suite green on Chromium — P0 · owner: nera · evidence: —
- [ ] **CHU-005** Security conformance suite green on Chromium — P0 · owner: nera · evidence: —
- [ ] **CHU-006** Helper entitlements unchanged, or the change is justified in an ADR — P0 · owner: nera · evidence: —
- [ ] **CHU-007** Forbidden-switch check and sandbox verification pass — P0 · owner: nera · evidence: —
- [ ] **CHU-008** Privacy: clean-profile packet capture shows no new background hosts — P0 · owner: nera · evidence: —
- [ ] **CHU-009** Extensions smoke (uBO Lite, Bitwarden) still install and work — P1 · owner: nera · evidence: —
- [ ] **CHU-010** Performance and binary size within budget — P1 · owner: nera · evidence: —
- [ ] **CHU-011** `THIRD_PARTY_NOTICES` regenerated — P0 · owner: nera · evidence: —
- [ ] **CHU-012** Ship via the normal or emergency release path; record the days-to-ship metric — P0 · owner: maintainer · evidence: —
