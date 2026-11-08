# ADR-0007: Continuous integration on GitHub-hosted runners

**Status:** Accepted · **Date:** 2026-11-05 · **Supersedes:** the private-phase decision to run CI on a self-hosted
runner (2026-10-25)

## Context

While Nera was private, its CI ran on a self-hosted macOS runner on the maintainer's machine. A public repository
accepts changes from anyone; once a change is merged, its tests run wherever CI runs. Signing keys and release
credentials must never be reachable from there.

## Decision

1. **Every public workflow runs on GitHub-hosted macOS runners** (free for public repositories). No self-hosted
   runner serves this repository.
2. **Pull requests from forks** run the full pipeline on the `pull_request` event (never `pull_request_target`),
   with a read-only token and no secrets.
3. **Least privilege:** workflows start with no permissions and grant the minimum per job; every action is pinned to
   a commit SHA; tools are installed at pinned versions with checksums (`scripts/ci/install-tools.sh`).
4. **Releases** run on a GitHub-hosted runner with secrets from a `release` environment that only the maintainer can
   approve.
5. If self-hosted capacity is ever needed (for example stable hardware for performance trends), it runs in
   ephemeral virtual machines under a separate macOS user without a personal keychain, restricted to named
   workflows, and never for pull requests.

## Consequences

- Performance numbers from shared hosted runners are noisy; benchmarks are run and published separately
  (`docs/perf/`).
- The pinned Chromium Embedded Framework is downloaded and cached per version (checked by SHA-256).
