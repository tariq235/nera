# 011 — Clean Room

Policy: [CLEAN_ROOM.md](../CLEAN_ROOM.md), [ADR-0001](../docs/adr/0001-clean-room.md).

- [x] **CR-001** Written clean-room policy (allowed / not allowed / process) — P0 · owner: nera · evidence: doc:CLEAN_ROOM.md
- [x] **CR-002** Other products' binaries and files derived from them are never committed (blocked by .gitignore) — P0 · owner: nera · evidence: file:.gitignore
- [x] **CR-003** No code, text or assets from other products are copied into Nera; behavior is described in our own words — P0 · owner: nera · evidence: doc:CLEAN_ROOM.md
- [x] **CR-004** Importer fixtures are synthetic, not real user data — P0 · owner: nera · evidence: file:Packages/NeraKit/Tests/ImportTests/Fixtures/StorableSidebar.sample.json
- [x] **CR-005** CI rejects Arc/Dia identifiers, bundle/team IDs, known identifiers, endpoints, and byte-identical Arc assets (SHA-256 fingerprints) in shipped sources — P0 · owner: nera · evidence: ci:scripts/ci/check-clean-room.py, file:scripts/ci/data/arc-asset-hashes.txt
- [x] **CR-009** CI rejects Arc/Dia product and feature names in user-facing text and in the app's name; nominative "Import from Arc" uses are explicitly marked — P0 · owner: nera · evidence: ci:scripts/ci/check-clean-room.py
- [x] **CR-006** PR template requires the clean-room confirmation — P1 · owner: nera · evidence: file:.github/pull_request_template.md
- [x] **CR-007** Original name, logo and visual identity (the icon is drawn by our own code) — P0 · owner: maintainer · evidence: file:scripts/brand/render-icon.swift
