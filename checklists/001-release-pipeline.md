# 001 — Release Pipeline

What the pipeline can *do*. Per-release signoff is the template in [012](012-release-signoff.md). Process: [release requirements](../docs/standards/release-requirements.md).

- [x] **REL-001** One command runs the full pre-merge gate locally (`make smoke`) — P0 · owner: nera · evidence: file:scripts/smoke.sh, file:Makefile
- [x] **REL-002** CI workflow runs unit, build, security gates, UI and iOS build on every PR — P0 · owner: nera · evidence: file:.github/workflows/ci.yml
- [x] **REL-003** CI on GitHub-hosted runners; pull requests from forks run the full pipeline without secrets — P0 · owner: nera · evidence: doc:docs/adr/0007-ci-github-hosted-runners.md
- [ ] **REL-004** Branch protection: all required checks green before merge (set on the public repository) — P0 · owner: maintainer · evidence: planned: later
- [ ] **REL-005** Developer ID signing in CI from a throwaway keychain — P0 · owner: nera · evidence: file:.github/workflows/release.yml, planned: needs REL-015 (Developer ID certificate)
- [x] **REL-006** Notarization + stapling of app and DMG (on the maintainer's Mac with the `nera-notary` profile; CI signing is REL-005) — P0 · owner: nera · evidence: file:scripts/release/make-dmg.sh, file:.github/workflows/release.yml
- [x] **REL-007** Sparkle 2 appcast with EdDSA signatures, staged rollout — P0 · owner: nera · evidence: test:UpdateTests/onlyCorrectlySignedFilesPass, test:UpdateTests/stagedRolloutReachesGroupsDayByDay, file:scripts/release/sign-update.swift, doc:docs/adr/0011-updates.md
- [x] **REL-008** SBOM (CycloneDX/SPDX) attached to every release — P0 · owner: nera · evidence: file:scripts/release/sbom.py, file:.github/workflows/release.yml
- [ ] **REL-009** SLSA build provenance attestation per artifact — P1 · owner: nera · evidence: file:.github/workflows/release.yml, planned: runs once the repo is public or on Enterprise Cloud (GitHub limit)
- [ ] **REL-010** Signed release tags — P1 · owner: maintainer · evidence: planned: later
- [x] **REL-012** Nightly / Beta / Stable channels — P1 · owner: nera · evidence: test:UpdateTests/picksTheNewestFittingUpdate, test:UpdateTests/channelsAcceptMoreStableReleases
- [ ] **REL-013** Emergency security release path documented and rehearsed (< 24 h) — P0 · owner: maintainer · evidence: doc:docs/release-emergency.md, planned: first rehearsal after REL-015
- [ ] **REL-014** iOS: TestFlight upload from CI — P1 · owner: nera · evidence: planned: roadmap
- [x] **REL-015** Apple Developer Program account active (Developer ID Application certificate) — P0 · owner: maintainer · evidence: file:scripts/release/make-dmg.sh
- [x] **REL-016** `THIRD_PARTY_NOTICES` generated from the dependency register (done) and bundled inside the app (with CEF) — P0 · owner: nera · evidence: file:THIRD_PARTY_NOTICES.md, ci:scripts/release/check-release-bundle.sh
- [x] **REL-017** Every public API has a doc comment, enforced by CI — P1 · owner: nera · evidence: ci:scripts/ci/check-public-docs.py
- [x] **REL-018** Architecture rules (layering, engine independence, forbidden APIs) enforced by CI — P0 · owner: nera · evidence: ci:scripts/ci/check-architecture.py
- [x] **REL-019** Formatting (swift format), lint (SwiftLint) and a warnings-as-errors build enforced in CI — P0 · owner: nera · evidence: file:.swift-format, file:.swiftlint.yml, file:.github/workflows/ci.yml
- [x] **REL-022** Automatic updates: checked daily, downloaded and verified in the background, installed on quit or with "Restart to Update"; the swap restores the old app if it fails — P0 · owner: nera · evidence: test:UpdateTests/swapWaitsForQuitThenReplacesTheApp, test:UpdateTests/stagesAndVerifiesARealDiskImage, doc:docs/adr/0011-updates.md
- [x] **REL-021** Release notes in every DMG: the newest entry stamps the build number into the app and ships inside the disk image — P0 · owner: nera · evidence: file:scripts/release/make-dmg.sh
- [x] **REL-020** API documentation builds with DocC and zero warnings (broken symbol links fail CI) — P1 · owner: nera · evidence: ci:scripts/ci/check-docc.sh
