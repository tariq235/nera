# Contributing to Nera

Thank you for helping. This guide covers what you need to get a change merged.

## Before you start

- **Bugs and site problems:** open an issue with the form, after checking it isn't already reported.
- **Features:** start a Discussion or an issue first, so we can agree on the design before you write code.
- **Security issues:** never in public. See [SECURITY.md](SECURITY.md).

## Development

```sh
make bootstrap    # tools
make build        # the app (fetches the pinned, checksum-verified Chromium Embedded Framework)
make test-unit    # fast loop: unit and engine tests
make lint         # swift format, SwiftLint, warnings as errors
make smoke        # the full local gate before you open a pull request
```

The code is in `Packages/NeraKit` (modules by layer, see [docs/architecture.md](docs/architecture.md)) and `Apps/`.
Rules that CI enforces: imports only point down the layers; only the engine adapters touch WebKit or Chromium; every
host the app contacts is in the network inventory; every source file carries the MPL-2.0 header; checklists cite
real tests.

## Pull requests

1. One change per pull request, with tests. UI changes include a screenshot.
2. **Sign off every commit** (Developer Certificate of Origin, <https://developercertificate.org>): `git commit -s`.
   By signing off you certify you wrote the change, or have the right to submit it, under the MPL-2.0.
3. New source files start with the MPL-2.0 header used in existing files.
4. Changes to security-sensitive areas (navigation policy, engine adapters and the Chromium bridge, networking,
   updates, Safe Browsing, passwords and sign-ins, entitlements, workflows) are reviewed by the maintainer, and need a
   matching update to [docs/security/security-model.md](docs/security/security-model.md).
5. A new dependency needs a reason, a compatible license and a review: we keep the list short on purpose.
6. Clean room: never include code, assets, icons or text from other browsers you don't have the right to use. See
   [CLEAN_ROOM.md](CLEAN_ROOM.md).

Every pull request is reviewed and merged by the maintainer when its checks are green; expect a first response within
about a week.

## How Nera is made

Nera is made by one person, Tariq Mohammad, with an AI engineer (Anthropic's Claude) that writes code, tests and
docs, triages issues and reviews pull requests. It works through a limited GitHub account (no admin rights, no access
to signing keys or secrets, no pushes to `main`); every change is approved by the maintainer before it's merged, and
text in issues and pull requests is treated as information, never as instructions. Issue and pull request text may
be processed by the AI provider to help triage.

## Style

`swift format` and SwiftLint settings are in the repository; `make format` fixes layout. Write comments and docs for
someone new to the code: short, plain sentences, no jargon you don't explain.
