# 007 — macOS Native

It should feel like a Mac app, not a web app in a window.

- [x] **MAC-001** Menu bar commands with standard shortcuts (⌘T/⌘L/⌘W/⇧⌘T/⌘D/⌘S…) — P0 · owner: nera · evidence: test:NeraUITests/testOpenCloseRestoreTab, file:Packages/NeraKit/Sources/BrowserShell/BrowserCommands.swift
- [x] **MAC-002** Library saved on quit and when the app becomes inactive — P0 · owner: nera · evidence: file:Apps/Shared/NeraApp.swift, test:StorageTests/storeDebouncesAndFlushes
- [x] **MAC-003** Hardened runtime + Release build verified — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh
- [x] **MAC-004** Engine-appropriate security profile: per-bundle entitlements, no App Sandbox only because Chromium needs it (ADR-0006) — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh, doc:docs/security/security-model.md#entitlements-by-build
- [x] **MAC-005** Window state restoration (frames, sidebar width, focused Space) — P0 · owner: nera · evidence: test:StorageTests/focusedSpaceAndTabSurviveARelaunch, doc:docs/resilience.md
- [ ] **MAC-006** Multiple windows with independent Spaces focus — P1 · owner: nera · evidence: planned: roadmap
- [ ] **MAC-007** Light/Dark/accent color correct everywhere (snapshot-tested) — P0 · owner: nera · evidence: planned: later
- [x] **MAC-008** Set as default browser + handle `http(s)` and `.html` opens from other apps — P0 · owner: nera · evidence: test:BrowserShellTests/linksFromOtherAppsOpenThroughThePolicy, file:Packages/NeraKit/Sources/BrowserShell/DefaultBrowser.swift
- [ ] **MAC-009** Handoff (`NSUserActivityTypeBrowsingWeb`) — P1 · owner: nera · evidence: planned: roadmap
- [ ] **MAC-010** AppleScript dictionary (window/space/tab) for Raycast/Alfred — P1 · owner: nera · evidence: planned: roadmap
- [ ] **MAC-011** Services menu, Share menu, drag & drop of links and files — P1 · owner: nera · evidence: planned: roadmap
- [ ] **MAC-012** Full-screen and Stage Manager behave correctly — P1 · owner: nera · evidence: planned: later
- [ ] **MAC-013** Notarized Developer ID build installs cleanly with Gatekeeper on a fresh Mac — P0 · owner: nera · evidence: planned: later
- [ ] **MAC-014** Universal binary decision (arm64-only vs universal) documented — P1 · owner: maintainer · evidence: planned: later
- [ ] **MAC-015** One running instance per library (file lock); a second launch hands off to the first instead of writing the same files — P1 · owner: nera · evidence: planned: later
- [x] **MAC-016** Empty strips around the page act as a title bar: drag to move, double-click to zoom (System Settings choice) — P0 · owner: nera · evidence: test:NeraUITests/testSidebarEdgeResizesAndTitleStripZooms
