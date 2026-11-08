# 010 — Threat Model Review

The model itself: [docs/security/threat-model.md](../docs/security/threat-model.md). This list tracks whether every component has been analyzed and its mitigations verified. Re-review whenever a trust boundary changes (new engine, new process, new network service, new parser of untrusted input).

- [x] **TM-001** Threat model v1 with assets, adversaries, trust boundaries and data-flow diagram — P0 · owner: nera · evidence: doc:docs/security/threat-model.md
- [x] **TM-002** STRIDE analysis for every current component — P0 · owner: nera · evidence: doc:docs/security/threat-model.md#stride-by-component
- [x] **TM-003** Every "High" threat maps to a tracked checklist item — P0 · owner: nera · evidence: doc:docs/security/threat-model.md#stride-by-component
- [ ] **TM-004** Chromium process model + helper boundaries added — P0 · owner: nera · evidence: planned: later
- [ ] **TM-005** Self-hosted CI runner threats reviewed (ephemeral VM, token scope, fork PRs) — P0 · owner: nera · evidence: planned: later
- [x] **TM-006** Release/update pipeline threats reviewed (key custody, release approval): two gates (Ed25519 + Developer ID), current + standby keys, offline backup, rotation without stranding installs; single-maintainer risk accepted and recorded — P0 · owner: maintainer · evidence: doc:docs/release/update-signing-key.md, test:UpdateTests/eitherTheCurrentOrTheStandbyKeyIsAccepted, doc:docs/adr/0011-updates.md
- [ ] **TM-007** External security review before public beta — P0 · owner: maintainer · evidence: planned: roadmap
- [ ] **TM-008** Extensions and sync threat sections written before those features start — P1 · owner: nera · evidence: planned: roadmap
