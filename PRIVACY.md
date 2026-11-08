# Privacy

Nera has no telemetry, no accounts and no ads. Your tabs, history, bookmarks, passwords and settings stay on your
Mac. Nera doesn't collect personal data, so there's nothing for us to sell or share.

## What Nera sends, and to whom

Besides the sites you visit, Nera contacts these services on its own:

| Service | What and why | Can you turn it off? |
|---|---|---|
| **Google Safe Browsing** | Threat lists are downloaded and kept on your Mac. Only when a site's address matches an entry are short fingerprints (4-byte hash prefixes) sent to Google to confirm; the address itself never leaves your Mac. Google sees your IP address and Nera's API key | Settings › Privacy |
| **GitHub** (update check and download) | Once a day: the signed update feed and, if there's a new version, the download. Nothing about you is sent | Settings › General |
| **Chrome Web Store** (Google) | Only when you install a Chrome extension | Don't install extensions |
| Your search engine | What you search for, sent to the engine you chose | Choose the engine in Settings |
| Chromium's own background requests | Three requests the embedded Chromium makes to Google services (component updates, a feature check, translation data); listed in the security model and monitored by a nightly audit | Not yet; we're working on removing them |

The complete, CI-enforced list is the network inventory in
[docs/security/security-model.md](docs/security/security-model.md).

## The project on GitHub

Issues, pull requests and discussions are public and hosted by GitHub under GitHub's privacy statement. The
maintainer uses an AI assistant (Anthropic's Claude) to help triage and review them, so their text may be processed
by Anthropic. Don't post private information in them.

## Contact

Questions about privacy: open a [Discussion](https://github.com/tariq235/nera/discussions), or report privately through
[GitHub](https://github.com/tariq235/nera/security/advisories/new) if it's sensitive.
