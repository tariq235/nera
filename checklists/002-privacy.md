# 002 — Privacy

Promise: **no data leaves the device unless the user asks for it.**

- [x] **PRV-001** Zero third-party SDKs (analytics, crash, flags, ads) in the app — P0 · owner: nera · evidence: file:Packages/NeraKit/Package.swift, ci:scripts/ci/check-network-inventory.sh
- [x] **PRV-002** No telemetry by default; every app-level host documented — P0 · owner: nera · evidence: ci:scripts/ci/check-network-inventory.sh, doc:docs/security/security-model.md#network-inventory
- [x] **PRV-003** Dependency register: CI fails when a third-party package appears without a reviewed, allowlisted license — P0 · owner: nera · evidence: ci:scripts/ci/check-licenses.py, file:scripts/ci/data/dependencies.json
- [x] **PRV-004** Search suggestions off by default, or sent only to the chosen engine after explicit opt-in (Nera sends none: the command bar suggests from local tabs, history and bookmarks only; no suggestion host in the network inventory) — P0 · owner: nera · evidence: doc:docs/security/security-model.md
- [ ] **PRV-005** Chromium: Google services disabled (sign-in, sync, metrics/UMA, field trials, component-update pings audited) — P0 · owner: nera · evidence: planned: later
- [ ] **PRV-006** Chromium: network inventory of the engine's own background requests on a clean profile (net log audit 2026-11-04: 3 of 6 background hosts stopped; the 3 remaining are disclosed in security-model.md per a nightly audit fails on any new host) — P0 · owner: nera · evidence: file:scripts/privacy/chromium-traffic.sh, file:.github/workflows/nightly.yml, doc:docs/security/security-model.md, planned: disclose in the privacy policy
- [x] **PRV-007** Logs redact URLs, titles, cookies, tokens and passwords (private by default; only Redact values public; no print/NSLog; Chromium logging off in Release) — P0 · owner: nera · evidence: ci:scripts/ci/check-log-redaction.py, test:DiagnosticsTests/urlsKeepOnlyTheirScheme
- [x] **PRV-008** Automated tests never read or write real user data (in-memory library, temp downloads folder, separate test bundle ID, synthetic fixtures) — P0 · owner: nera · evidence: test:NeraUITests/testLaunchShowsSidebarAndEmptyState, file:Packages/NeraKit/Sources/BrowserShell/AppModel.swift, file:Packages/NeraKit/Tests/ImportTests/Fixtures/StorableSidebar.sample.json
- [x] **PRV-009** Arc import reads only the file the user picks — P0 · owner: nera · evidence: file:Packages/NeraKit/Sources/BrowserShell/RootView.swift
- [ ] **PRV-010** Diagnostics are local-only; export is a user action showing exactly what's included — P1 · owner: nera · evidence: planned: later
- [x] **PRV-011** Private sessions: separate in-memory cookie jar, storage and cache; nothing on disk (engine level; history arrives with the History feature) — P0 · owner: nera · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [ ] **PRV-012** "Clear browsing data" per profile and per time range — P1 · owner: nera · evidence: planned: roadmap
- [ ] **PRV-013** Global Privacy Control (`Sec-GPC`) sent by default — P1 · owner: nera · evidence: planned: later
- [ ] **PRV-014** Third-party cookie blocking default decided and documented per engine — P1 · owner: nera · evidence: planned: later
- [ ] **PRV-015** Privacy policy page and App Store privacy label written — P0 · owner: maintainer · evidence: planned: roadmap
