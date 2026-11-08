# Security requirements (normative)

**MUST** = release-blocking. **SHOULD** = needs an ADR to skip. Verification status lives in [checklist 000](../../checklists/000-browser-security.md) (and 002 for privacy). Rationale: [threat model](../security/threat-model.md).

## Transport

| ID | Requirement | Verified by |
|---|---|---|
| SR-001 | Main-frame `http:` navigations MUST be upgraded to HTTPS by default; loopback hosts are exempt; per-host exceptions MUST be user-granted | SEC-001, SEC-002 |
| SR-002 | Nera code MUST NOT override server-trust evaluation (no `URLCredential(trust:)` accept-all, no Chromium cert-error callbacks returning "continue" without a user decision on a non-HSTS host) | SEC-004, SEC-005 |
| SR-003 | HSTS, mixed-content blocking and revocation checking MUST be active on every engine | SEC-003, SEC-006, SEC-007 |
| SR-004 | Nera's own endpoints MUST use HTTPS and SHOULD be pinned | SEC-008 |

## Navigation

| ID | Requirement | Verified by |
|---|---|---|
| SR-010 | Every main-frame navigation MUST pass `NavigationPolicy` in both engine adapters | SEC-019 |
| SR-011 | `javascript:`/`vbscript:` MUST be blocked from typing and from pages | SEC-010 |
| SR-012 | Top-level `data:` only when typed; `file:` never from web content | SEC-011, SEC-012 |
| SR-013 | URLs with embedded credentials MUST be blocked | SEC-013 |
| SR-014 | External app schemes MUST need a user gesture and confirmation | SEC-014 |
| SR-015 | Script-opened popups MUST need a user gesture | SEC-015 |
| SR-016 | The address bar MUST show the committed URL (pending URLs only for user-initiated navigations) | SEC-016 |
| SR-017 | Safe Browsing MUST be on by default | SEC-018 |

## Isolation

| ID | Requirement | Verified by |
|---|---|---|
| SR-020 | Engine sandboxes MUST stay enabled; forbidden Chromium switches MUST be rejected in Release | SEC-020, SEC-026 |
| SR-021 | Site isolation MUST be on (Chromium) | SEC-021 |
| SR-022 | Nera MUST NOT weaken CSP, SameSite, COOP/COEP or nosniff (verified by conformance tests) | SEC-022 to SEC-025 |
| SR-023 | Profiles MUST have isolated website data; private windows MUST leave nothing on disk | SEC-030, SEC-031 |

## Data at rest

| ID | Requirement | Verified by |
|---|---|---|
| SR-030 | The library MUST be written atomically; unreadable files MUST be preserved; newer schemas MUST NOT be downgraded | SEC-032, SEC-033 |
| SR-031 | Secrets MUST be stored only in the Keychain | SEC-034 |
| SR-032 | Nera MUST NOT implement its own password vault | SEC-035 |

## Requests from web content

| ID | Requirement | Verified by |
|---|---|---|
| SR-040 | Permission requests MUST be per-origin, revocable, and default-deny | SEC-040, SEC-041 |
| SR-041 | JS dialogs MUST show their origin and be throttled | SEC-042 |
| SR-042 | Downloads MUST be quarantined and never auto-opened | SEC-044 |

## Binary & process

| ID | Requirement | Verified by |
|---|---|---|
| SR-050 | Every shipped Mach-O MUST have the hardened runtime; the main app MUST have library validation | SEC-050, SEC-053 |
| SR-051 | Entitlements MUST match the per-bundle allowlist; `disable-library-validation`, `allow-unsigned-executable-memory`, `disable-executable-page-protection` and `allow-dyld-environment-variables` are forbidden | SEC-051, SEC-052 |
| SR-052 | Renderer crashes MUST NOT lose user data or crash the main process | SEC-055 |

## Supply chain & updates

| ID | Requirement | Verified by |
|---|---|---|
| SR-060 | Updates MUST be EdDSA-signed and Apple-signed/notarized | SEC-060, SEC-061 |
| SR-061 | App-level network hosts MUST be on the inventory and enforced at runtime | SEC-062, SEC-063 |
| SR-062 | External binaries (CEF) MUST be pinned by version and SHA-256 | ENG-021 |
| SR-063 | CI MUST scan for secrets and vulnerable dependencies on every PR | SEC-064, SEC-065 |
| SR-064 | Chromium security releases MUST ship within 7 days (48 h if exploited) | SEC-066 |
| SR-065 | Every parser of untrusted input MUST be fuzzed | SEC-067 |

## Privacy

| ID | Requirement | Verified by |
|---|---|---|
| SR-070 | No third-party analytics/crash/flag SDKs; no telemetry by default | PRV-001, PRV-002 |
| SR-071 | Logs and crash reports MUST NOT contain URLs, titles or personal data | SEC-070, PRV-007 |
| SR-072 | Chromium's Google-service and metrics endpoints MUST be disabled and audited | PRV-005, PRV-006 |
