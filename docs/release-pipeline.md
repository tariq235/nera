# Release pipeline

How a Nera release is built, signed and published. Everything runs on GitHub-hosted macOS runners
([ADR-0007](adr/0007-ci-github-hosted-runners.md)).

## Every pull request

`.github/workflows/ci.yml`: format and lint, architecture and policy checks (clean room, licenses, MPL headers,
network inventory, log redaction, documentation), secret scanning, dependency check, unit and engine tests, a Release
build with its security gates (entitlements, bundled notices, no Debug test hooks, static analysis), the real-engine
self-test, and size budgets. CodeQL, OpenSSF Scorecard and dependency review run alongside. Pull requests from forks
run all of it with a read-only token and no secrets.

## A release

1. The maintainer adds the release notes to `CHANGELOG.md` and pushes a signed version tag (`v0.2.0`).
2. `.github/workflows/release.yml` waits for the maintainer's approval of the `release` environment, which holds
   the signing secrets (set, and checked first, by `scripts/release/set-release-secrets.sh` on the maintainer's Mac).
3. It downloads and verifies the pinned Chromium Embedded Framework (SHA-256, never from a cache), runs the tests on
   the tagged commit, and builds the app with the hardened runtime.
4. Release gates: entitlements, bundled third-party notices, no Debug-only test hooks, and the source link in the
   app must be this public repository (MPL-2.0 §3.2).
5. Developer ID signing and Apple notarization of the app and the disk image.
6. The update signature (Ed25519) and the update feed (`appcast.xml`, served from the release's own downloads).
7. A software bill of materials (CycloneDX), SHA-256 checksums and a build provenance attestation.
8. A **draft** GitHub release with all of the above; the maintainer reviews it and publishes it. From then on,
   installed copies of Nera find the update within a day (they read `releases/latest/download/appcast.xml`).

Beta tags (`v0.1.0-beta.1`) are published as regular releases, because GitHub's "latest" skips prereleases and
installed copies would never see them; only nightly builds are marked as prereleases.

## If a release is bad

`docs/release-emergency.md`: pull it from the update feed (`scripts/release/make-appcast.py --remove`), then ship a
fixed build. Signing keys and their backup: [docs/release/update-signing-key.md](release/update-signing-key.md).
