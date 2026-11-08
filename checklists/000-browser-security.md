# 000 — Browser Security

Rules: [security requirements](../docs/standards/security-requirements.md) · Threats: [threat model](../docs/security/threat-model.md).
"Engine" items must pass on **both** engines (WebKit and Chromium) through the security conformance suite.

## Transport & certificates

- [x] **SEC-001** HTTP is upgraded to HTTPS by default (HTTPS-Only), with loopback exempt — P0 · owner: nera · evidence: test:SecurityPolicyTests/httpIsUpgradedInHTTPSOnlyMode, test:SecurityPolicyTests/loopbackAndExceptionsStayHTTP
- [x] **SEC-002** HTTPS-Only interstitial with a per-host "Continue over HTTP" choice (also when the secure load hasn't started after 5 s; the choice lasts the session and applies to every page at once) — P0 · owner: nera · evidence: test:BrowserShellTests/secureConnectionUnavailableOffersHTTPForThatSite, test:BrowserShellTests/aSecureLoadThatNeverAnswersFallsBackToTheChoice, test:BrowserShellTests/httpExceptionsAreSharedByEveryCopyOfThePolicy
- [ ] **SEC-003** HSTS honored, including the preload list — P0 · owner: engine · evidence: planned: later
- [x] **SEC-004** Certificate validation never bypassed in our code (server-trust always system default; trust overrides fail CI) — P0 · owner: nera · evidence: test:WebKitEngineTests/serverTrustIsAlwaysLeftToTheSystem, ci:scripts/ci/check-architecture.py
- [x] **SEC-005** Certificate errors show a full-page interstitial; no bypass on HSTS hosts (stricter: Nera offers no bypass on any host, on either engine; unreachable sites get their own page with Try Again) — P0 · owner: nera · evidence: test:WebKitEngineTests/certificateFailuresAreRecognized, test:BrowserShellTests/certificateErrorsOnlyGoBackAndUnreachableSitesRetry, ci:scripts/ci/engine-self-test.sh
- [ ] **SEC-006** Revocation checking active (OS trust evaluation / Chromium CRLSets) — P1 · owner: engine · evidence: planned: later
- [x] **SEC-007** Mixed active content blocked (both engines, S05); passive content upgraded or flagged by the engine — P0 · owner: engine · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [ ] **SEC-008** Certificate pinning for *Nera's own* endpoints (update feed, sync relay) — P1 · owner: nera · evidence: planned: later
- [x] **SEC-009** "Not Secure" indicator for http:// pages — P1 · owner: nera · evidence: test:SecurityPolicyTests/displayURL

## Navigation & URL safety

- [x] **SEC-010** `javascript:` URLs blocked from the address bar and from pages — P0 · owner: nera · evidence: test:SecurityPolicyTests/javascriptURLsAreAlwaysBlocked, test:WebKitEngineTests/conformance, test:NeraUITests/testJavascriptURLIsBlocked
- [x] **SEC-011** Top-level `data:` navigations allowed only when typed — P0 · owner: nera · evidence: test:SecurityPolicyTests/dataURLsOnlyTopLevelWhenTyped
- [x] **SEC-012** Pages can't navigate to `file:` URLs — P0 · owner: nera · evidence: test:SecurityPolicyTests/fileURLsOnlyWhenTyped
- [x] **SEC-013** Links with embedded credentials (`user:pass@host`) blocked — P0 · owner: nera · evidence: test:SecurityPolicyTests/embeddedCredentialsAreBlocked
- [x] **SEC-014** External app schemes need a user gesture and confirmation — P0 · owner: nera · evidence: test:SecurityPolicyTests/externalSchemesNeedGestureAndConfirmation
- [x] **SEC-015** Popups need a user gesture (script-opened windows blocked) — P0 · owner: nera · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh, doc:checklists/005-browser-engine.md#conformance-matrix
- [ ] **SEC-016** Address bar shows the committed URL; pending-URL rules prevent spoofing (implemented; spoof scenario test needs LocalTestServer) — P0 · owner: nera · evidence: file:Packages/NeraKit/Sources/WebKitEngine/WebKitPage.swift, planned: later
- [ ] **SEC-017** IDN homograph defense (punycode for mixed-script hosts) — P1 · owner: nera · evidence: planned: later
- [x] **SEC-018** Safe Browsing enabled (WebKit: Apple's Fraudulent Website Warning; Chromium: Google Safe Browsing v5, Local List mode, page held until verified, warning with no way past malware) — P0 · owner: nera · evidence: test:SafeBrowsingTests/canonicalizesLikeGoogle, test:SafeBrowsingTests/aRealListDecodesToGooglesChecksum, test:SafeBrowsingTests/partialUpdatesRemoveThenAddAndAreVerified, test:SafeBrowsingTests/aListedPageIsFoundAndOnlyItsPrefixLeavesTheMac, test:SafeBrowsingTests/googlesTestPagesAreFlaggedAndOrdinaryPagesArent, test:BrowserShellTests/aPhishingPageIsStoppedAndWarnedAbout, test:BrowserShellTests/malwareHasNoWayPast, doc:docs/release/safe-browsing-key.md
- [x] **SEC-019** Same navigation policy enforced identically by both engine adapters — P0 · owner: nera · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh, test:ChromiumEngineTests/pageInitiatedNavigationsGoThroughTheSharedPolicy

## Web platform isolation (verify, never weaken)

- [ ] **SEC-020** Renderer processes sandboxed (WebKit WebContent; Chromium seatbelt) — P0 · owner: engine · evidence: planned: later automated sandbox_check test (the CEF prototype showed every Chromium child process sandboxed)
- [ ] **SEC-021** Site isolation on (Chromium) / process-per-origin behavior documented (WebKit) — P0 · owner: engine · evidence: planned: later
- [x] **SEC-022** CSP enforced — P0 · owner: engine · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [ ] **SEC-023** SameSite cookie defaults (Lax) enforced — P0 · owner: engine · evidence: planned: decide Lax-by-default for WebKit (Chromium already treats SameSite-less cookies as Lax; explicit Lax is enforced on both engines per S08)
- [ ] **SEC-024** COOP / COEP / cross-origin isolation (`crossOriginIsolated`) behave per spec — P1 · owner: engine · evidence: planned: later
- [x] **SEC-025** `X-Content-Type-Options: nosniff` honored (no MIME sniffing of scripts/styles) — P0 · owner: engine · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [x] **SEC-026** Forbidden Chromium switches (`--no-sandbox`, `--disable-web-security`, …) rejected in Release — P0 · owner: nera · evidence: ci:scripts/ci/engine-self-test.sh, file:Apps/macOS/Chromium/NRAChromium.mm

## Storage, profiles & private browsing

- [x] **SEC-030** Profiles have isolated cookies/storage/cache — P0 · owner: nera · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [x] **SEC-031** Private windows leave nothing on disk after close — P0 · owner: nera · evidence: test:WebKitEngineTests/conformance, ci:scripts/ci/engine-self-test.sh
- [x] **SEC-032** Library file written atomically; a corrupt file is preserved, never overwritten — P0 · owner: nera · evidence: test:StorageTests/corruptFileIsMovedAsideNotDeleted, test:StorageTests/roundTrip
- [x] **SEC-033** A newer-schema library is refused (no silent downgrade data loss) — P1 · owner: nera · evidence: test:StorageTests/newerSchemaRefusesToLoad
- [ ] **SEC-034** Secrets (tokens, keys) only in the Keychain — P0 · owner: nera · evidence: planned: later
- [ ] **SEC-035** No in-house password vault: system AutoFill/Keychain/passkeys only — P1 · owner: nera · evidence: planned: later
- [ ] **SEC-036** iOS library file protection (`completeUntilFirstUserAuthentication`) verified on device — P1 · owner: nera · evidence: planned: later

## Permissions, dialogs & downloads

- [x] **SEC-040** Per-origin permission manager (camera, mic, location, notifications, clipboard-read), revocable — P0 · owner: nera · evidence: test:PermissionsTests/rememberedAnswersApplyAndOneDenialDenies, test:PermissionsTests/decisionsBelongToOneProfileAndOneOrigin, test:PermissionsTests/decisionsCanBeRevoked, test:ChromiumEngineTests/permissionRequestsBecomeDefaultDenyRequests
- [x] **SEC-041** Engine requests are default-deny if the UI never answers (`Decision` fallback on release) — P0 · owner: nera · evidence: test:EngineKitTests/releasingAnUnansweredDecisionAppliesTheFallback, test:PageLifecycleTests/discardingATabDeniesItsPendingRequests, test:WebKitEngineTests/conformance
- [x] **SEC-042** JS dialogs attributed to their origin, with flood protection — P0 · owner: nera · evidence: test:PageLifecycleTests/dialogFloodsAreAutoCancelledUntilTheNextNavigation, test:SecurityPolicyTests/allowsUpToTheLimitThenSuppressesUntilReset, test:NeraUITests/testAlertIsShownWithItsOriginAndPageContinues
- [ ] **SEC-043** Fullscreen and pointer-lock entry shows an unspoofable notice — P1 · owner: nera · evidence: planned: later
- [x] **SEC-044** Downloads get the quarantine attribute and are never auto-opened — P0 · owner: nera · evidence: test:DownloadsTests/finishedDownloadsGetTheQuarantineAttribute, test:PageLifecycleTests/dangerousDownloadsWaitForTheUserAndFinishedOnesAreReported, ci:scripts/ci/check-architecture.py
- [x] **SEC-045** Dangerous file types warn before saving — P1 · owner: nera · evidence: test:DownloadsTests/dangerousTypesNeedConfirmation, test:PageLifecycleTests/dangerousDownloadsWaitForTheUserAndFinishedOnesAreReported
- [x] **SEC-046** Download filenames sanitized (path traversal, bidi spoofing, hidden files) and never overwrite — P0 · owner: nera · evidence: test:DownloadsTests/sanitizes, test:DownloadsTests/destinationAlwaysStaysInsideTheDirectory, test:DownloadsTests/neverOverwritesExistingFiles

## Process & binary hardening

- [x] **SEC-050** Hardened runtime on the shipped app, verified in CI — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh
- [x] **SEC-051** Entitlement allowlist with forbidden entitlements, enforced in CI (every bundle: app, Chromium helpers, CEF framework) — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh
- [x] **SEC-052** Per-bundle entitlement allowlist covering every Chromium helper — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh, file:scripts/engine/embed-cef.sh
- [x] **SEC-053** Library validation on in the main app (hardened runtime on every bundle; `disable-library-validation` forbidden) — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh
- [x] **SEC-054** Crash loop → safe mode (no automatic page restore, WebKit fallback, banner) — P1 · owner: nera · evidence: test:StorageTests/twoFailedLaunchesInARowStartSafeMode, test:StorageTests/safeModeDeselectsEveryTab
- [x] **SEC-055** Renderer crash handled ("page stopped working" view + reload), no data loss — P0 · owner: nera · evidence: test:PageLifecycleTests/crashedPagesAreMarkedAndReloadRecreatesThem
- [x] **SEC-056** Developer tools / Web Inspector off by default, on only by explicit user choice (Settings › Advanced or a confirmation); pages can't open them; no remote debugging port — P1 · owner: nera · evidence: test:PageLifecycleTests/theSettingReachesNewAndExistingPages, ci:scripts/ci/check-architecture.py
- [x] **SEC-073** ChromiumEngine uses Nera's own Keychain item for cookie/password encryption (never the shared "Chromium Safe Storage") — P0 · owner: nera · evidence: ci:scripts/ci/engine-self-test.sh, file:Apps/macOS/Chromium/CEFBackend.swift
- [x] **SEC-074** Only the Chromium Renderer helper holds `allow-jit`; GPU and all other bundles hold no entitlements — P0 · owner: nera · evidence: ci:scripts/ci/check-entitlements.sh, file:Apps/macOS/ChromiumHelper/Renderer.entitlements

## Updates & supply chain

- [x] **SEC-060** Updates EdDSA-signed and Apple-signed; HTTPS feed: a download installs only with the exact length, a valid Ed25519 signature, and a Developer ID signature of the same team and bundle ID (ADR-0011 amendment) — P0 · owner: nera · evidence: test:UpdateTests/onlyCorrectlySignedFilesPass, test:UpdateTests/updatesMustBeSignedBySameTeamAndBundleID, test:UpdateTests/stagesAndVerifiesARealDiskImage, doc:docs/adr/0011-updates.md
- [ ] **SEC-061** Release builds notarized and stapled (done by hand for every DMG since build 1; not yet verified by CI) — P0 · owner: nera · evidence: file:scripts/release/make-dmg.sh, planned: CI verification with REL-005
- [x] **SEC-062** Every app-level network host listed in the network inventory, enforced in CI — P0 · owner: nera · evidence: ci:scripts/ci/check-network-inventory.sh
- [x] **SEC-063** Runtime host allowlist for app-level requests (not just a source scan) — P0 · owner: nera · evidence: test:NetworkingTests/refusedRequestsFailBeforeConnecting, test:NetworkingTests/redirectsToUnlistedHostsAreRefused, ci:scripts/ci/check-architecture.py, ci:scripts/ci/check-network-inventory.sh
- [x] **SEC-064** Secrets scanning (gitleaks, full git history) on every PR — P0 · owner: nera · evidence: ci:scripts/ci/check-secrets.sh
- [x] **SEC-065** Dependency vulnerability scan (OSV-Scanner over every SwiftPM lockfile) on every PR — P0 · owner: nera · evidence: ci:scripts/ci/check-dependencies.sh
- [ ] **SEC-066** Chromium security rebase SLA met (≤7 days; ≤48 h if exploited) — P0 · owner: maintainer · evidence: planned: later
- [x] **SEC-067** Fuzzing of every untrusted-input parser (omnibox, importer, policy, storage decode) — P0 · owner: nera · evidence: test:BrowserCoreTests/randomInputNeverEscapesTheSearchEngine, test:ImportTests/damagedSidebarFilesParseOrFailCleanly, test:SecurityPolicyTests/pagesNeverReachDangerousSchemes, test:StorageTests/damagedLibrariesLoadOrAreMovedAside
- [x] **SEC-068** Static analysis (CodeQL + `xcodebuild analyze`) on every PR: CodeQL (security-extended) on Swift; the clang analyzer on the Chromium bridge and helper, failing on any finding — P0 · owner: nera · evidence: ci:scripts/ci/check-static-analysis.sh, file:.github/workflows/codeql.yml
- [ ] **SEC-069** Reproducible builds verified (unsigned outputs match) — P1 · owner: nera · evidence: planned: later
- [x] **SEC-070** Crash reports and logs scrubbed of URLs and personal data: no crash-reporting SDK (macOS keeps reports on the Mac, users attach one to feedback themselves), and log redaction is enforced in CI — P0 · owner: nera · evidence: ci:scripts/ci/check-log-redaction.py
- [x] **SEC-072** CEF/Chromium version checked against Chromium security releases in CI (nightly: fails when a newer stable CEF exists) — P0 · owner: nera · evidence: ci:scripts/ci/check-cef-version.py, file:.github/workflows/nightly.yml

## Future surfaces (P0 when the feature lands)

- [ ] **SEC-080** Extensions: permission review at install; no silent permission upgrades — P1 · owner: nera · evidence: planned: roadmap
- [ ] **SEC-081** Sync: end-to-end encrypted fields; we never hold readable user data — P1 · owner: nera · evidence: planned: roadmap
