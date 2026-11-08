# Security policy

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through
[GitHub's private vulnerability reporting](https://github.com/tariq235/nera/security/advisories/new). Include the Nera version, the macOS
version, steps to reproduce, and the impact you see.

Nera is made by one person, so these are honest targets, not guarantees:

| | Target |
|---|---|
| Acknowledgement | within a few days |
| First assessment and severity | within about a week |
| Fix | as fast as the severity demands; critical and actively exploited issues first |
| Chromium security updates | adopted as soon as practical after each stable security release (aim: within 7 days, faster when exploited) |
| Credit | in the advisory and release notes, if you'd like |

## How fixes are disclosed

Fixes are prepared in a private security advisory, released, and then the advisory (and a CVE where appropriate) is
published. Please give us a reasonable time to ship a fix before you publish details.

## Supported versions

Only the latest release. Nera updates itself, and fixes aren't backported.

## Scope

In scope: the Nera app, its updates and release process, and the code in this repository.
Out of scope: bugs in Chromium or WebKit themselves (please report them to Google or Apple, and tell us so we can
ship their fix quickly), and sites' own security.

How Nera is designed to be secure: [docs/security/security-model.md](docs/security/security-model.md).
