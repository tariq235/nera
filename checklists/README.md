# Checklists

A ticked box here means **proven**, not "we think so". `scripts/ci/check-checklists.py` (`make checklists`) runs in CI and rejects any ticked item without evidence that exists.

## Item format

```
- [x] **SEC-014** HTTPS-Only upgrade — P0 · owner: nera · evidence: test:SecurityPolicyTests/httpIsUpgradedInHTTPSOnlyMode
- [ ] **SEC-030** Certificate errors show an interstitial — P0 · owner: nera · evidence: planned: later
```

| Field | Values |
|---|---|
| ID | `PREFIX-NNN`, unique across all checklists. Never reuse a retired ID |
| Priority | **P0** = blocks the release gate / a release · **P1** = needed before 1.0 · **P2** = nice to have |
| Owner | `nera` (our code) · `engine` (WebKit/Chromium does it; we verify and never weaken it) · `os` (macOS/iOS does it) · `maintainer` (a human/business action) |
| Evidence | Comma-separated: `test:<TestTarget>/<function>` · `ci:<script path>` · `doc:<path>` · `file:<path>` · `planned: <milestone>` |

Rules the validator enforces:
1. A ticked item cites at least one `test:`, `ci:`, `doc:` or `file:`, and no `planned:`.
2. Every cited test function and path must exist.
3. In **000 Browser Security**, a ticked **P0** item must cite a `test:` or `ci:`. A document alone doesn't prove a security property.
4. Template checklists (marked `<!-- checklist: template -->`) are copied per use and only format-checked.

`owner: engine` items still need *our* evidence: a conformance test showing the engine behaves correctly in Nera, on **both** engines.

## Index

| # | Checklist | Kind | In release gate |
|---|---|---|---|
| 000 | [Browser Security](000-browser-security.md) | status | ✅ |
| 001 | [Release Pipeline](001-release-pipeline.md) | status | |
| 002 | [Privacy](002-privacy.md) | status | ✅ |
| 003 | [Accessibility](003-accessibility.md) | status | |
| 004 | [Performance](004-performance.md) | status | |
| 005 | [Browser Engine](005-browser-engine.md) | status (parity matrix) | ✅ |
| 006 | [Chromium Upgrade](006-chromium-upgrade.md) | template, per upgrade | |
| 007 | [macOS Native](007-macos-native.md) | status | ✅ |
| 008 | [iOS & iPadOS](008-ios.md) | status | |
| 009 | [Feature Complete](009-feature-complete.md) | status | |
| 010 | [Threat Model Review](010-threat-model-review.md) | status | ✅ |
| 011 | [Clean Room](011-clean-room.md) | status | ✅ |
| 012 | [Release Signoff](012-release-signoff.md) | template, per release | |

**release gate** (lifts the feature freeze) = every P0 item in the ✅ lists is ticked: `scripts/ci/check-checklists.py --gate foundation`.

Normative rules live in [`docs/standards/security-requirements.md`](../docs/standards/security-requirements.md) (`SR-xxx`). Checklists track whether each rule is *verified*.
