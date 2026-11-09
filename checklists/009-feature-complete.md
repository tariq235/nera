# 009 — Feature Complete

"Can someone switch to Nera and never go back?" Ticked = shipped **and** covered by automated tests on every engine it applies to.
Order of work: [roadmap](../docs/roadmap.md).

> **Feature freeze:** no new visible features until the release gate passes ([checklists/README](README.md)). Items below marked `planned: roadmap` start after the gate.

## Core (exists today)

- [x] **FEAT-001** Spaces: create, switch (⌥⌘←/→, ⌃1–9), delete (never the last one) — P0 · owner: nera · evidence: test:BrowserCoreTests/adjacentSpaceWrapsAround, test:BrowserCoreTests/selectingSpaceRestoresMostRecentTab, test:BrowserCoreTests/deletingSpaceDiscardsItsPages, test:BrowserCoreTests/cannotDeleteLastSpace
- [x] **FEAT-002** Pinned vs Today sections; ⌘W archives Today tabs and unloads pinned ones — P0 · owner: nera · evidence: test:BrowserCoreTests/closingTodayTabArchivesItAndSelectsNeighbor, test:BrowserCoreTests/closingPinnedTabKeepsItButUnloads, test:NeraUITests/testPinnedTabSurvivesClose
- [x] **FEAT-003** Auto-archive of Today tabs after 12 h of inactivity — P0 · owner: nera · evidence: test:BrowserCoreTests/archiveSweepRemovesOnlyStaleUnselectedTodayTabs
- [x] **FEAT-004** Restore last closed tab (⇧⌘T) — P0 · owner: nera · evidence: test:BrowserCoreTests/restoreLastClosedReopensAtTop, test:NeraUITests/testOpenCloseRestoreTab
- [x] **FEAT-005** Command bar: URL vs search detection, new tab (⌘T) / current tab (⌘L) — P0 · owner: nera · evidence: test:BrowserCoreTests/urls, test:BrowserCoreTests/searches, test:BrowserCoreTests/currentTabDispositionNavigatesSelectedTab, test:NeraUITests/testOpenCloseRestoreTab
- [x] **FEAT-006** Command bar "switch to open tab" results: a strong match (the site, or the start of its site or title) comes first on ⌘T, so Return goes to the open tab instead of a duplicate — P0 · owner: nera · evidence: test:BrowserCoreTests/typingASiteThatsOpenFindsItsTabFirstAndStrongly, test:BrowserCoreTests/weakMatchesDontJumpAhead
- [x] **FEAT-007** Favorites grid (move in/out) — P0 · owner: nera · evidence: test:BrowserCoreTests/favoritesMoveOutOfSpaceAndBack
- [x] **FEAT-008** Pin/unpin (⌘D) and reset a pinned tab to its home URL — P0 · owner: nera · evidence: test:BrowserCoreTests/pinningRemembersHomeURLAndResetReturnsToIt
- [x] **FEAT-009** Folders: create, expand/collapse, nested tabs — P0 · owner: nera · evidence: test:BrowserCoreTests/folderToggleAndNestedTabRemoval
- [x] **FEAT-010** Tab cycling (⌥⌘↑/↓) — P1 · owner: nera · evidence: test:BrowserCoreTests/tabCyclingWraps
- [x] **FEAT-011** One-click Arc import: Spaces, pinned tree, folders, splits, Today, Favorites — P0 · owner: nera · evidence: test:ImportTests/importsPinnedTreeWithFolderAndSplit, test:ImportTests/importsFavoritesAndReport, test:ImportTests/importedLibraryFeedsReducer
- [ ] **FEAT-012** Sidebar show/hide (⌘S) UI-tested — P1 · owner: nera · evidence: planned: later
- [x] **FEAT-050** Sidebar width: drag its edge (200–420 pt, kept per Mac); adjustable with VoiceOver — P1 · owner: nera · evidence: test:NeraUITests/testSidebarEdgeResizesAndTitleStripMovesTheWindow

## Must-have to switch (after the release gate)

- [x] **FEAT-020** Permissions UI (site info popover, Settings → Site Settings with defaults and per-site exceptions, Allow This Time, revoke) — P0 · owner: nera · evidence: test:PermissionsTests/blockingByDefaultDeniesWithoutAskingButSitesCanBeAllowed, test:NeraUITests/testSiteSettingsCanBlockCameraByDefault
- [x] **FEAT-021** Downloads tray (progress, cancel, retry, Show in Finder, clear; ⌥⌘L) — P0 · owner: nera · evidence: test:PageLifecycleTests/downloadsCanBeCancelledRetriedAndCleared, test:NeraUITests/testDownloadAppearsInTrayAndCanBeCleared
- [x] **FEAT-022** History + command bar ranking (SQLite per profile, frecency search, ⌘Y window, Recently Closed, clear by range, 90-day retention, never for private pages) — P0 · owner: nera · evidence: test:StorageTests/searchMatchesEveryWordAndRanksByFrecency, test:PageLifecycleTests/persistentPagesRecordVisitsAndTitlesPrivatePagesNothing, test:NeraUITests/testHistoryShowsRecentlyClosedTabs
- [x] **FEAT-023** Profiles UI with per-profile engine choice (create, rename, delete with all data, move Spaces between profiles) — P0 · owner: nera · evidence: test:BrowserCoreTests/deletingAProfileRemovesEverythingItOwns, test:NeraUITests/testCreatingAProfileAddsItsSpace
- [x] **FEAT-024** Bookmarks + import from Chrome/Arc/Brave/Edge/Safari/Firefox or HTML (bookmarks, history), HTML export, manager (⌥⌘B), ⇧⌘D — P0 · owner: nera · evidence: test:ImportTests/chromiumBookmarksKeepFoldersAndDropBookmarklets, test:ImportTests/firefoxBookmarksAndHistoryFromPlaces, test:ImportTests/bookmarksHTMLRoundTrips, test:ImportTests/addRenameMoveDeleteAndImport
- [x] **FEAT-025** Split View UI (⌃⌘N new tab in split, split existing tabs, up to 4 panes, side by side or stacked, separate) — P0 · owner: nera · evidence: test:BrowserCoreTests/existingTabsCanBeSplitSeparatedAndRotated, test:NeraUITests/testSplitViewShowsBothTabs
- [x] **FEAT-026** DevTools (Chromium native window via ⌥⌘I and Inspect Element; Web Inspector via Inspect Element on WebKit), off until the user turns them on — P0 · owner: nera · evidence: test:PageLifecycleTests/theSettingReachesNewAndExistingPages, test:BrowserCoreTests/developerToolsAreOffUntilTurnedOn
- [ ] **FEAT-027** Passkeys + password AutoFill via system APIs — P0 · owner: nera · evidence: test:ChromiumEngineTests/refusalsHappenBeforeTheAuthenticator, test:PasskeysTests/relyingPartyMustBeTheHostOrAParentDomain, doc:docs/security/passkeys.md, planned: Apple's passkey entitlement (requested) and the entitled release build
- [ ] **FEAT-028** Sync (CloudKit, end-to-end encrypted fields) — P0 · owner: nera · evidence: planned: roadmap
- [x] **FEAT-029** Chrome extensions (Chromium engine; per ADR-0009): Extension Manager — Web Store link or CRX install with CRX3 developer + store signature checks, enable/remove, popups, one extensions profile (ADR-0012) — P0 · owner: nera · evidence: test:ExtensionsTests/validStorePackagesVerifyAndKeepTheirID, test:ExtensionsTests/tamperedUnsignedOrMislabelledPackagesAreRefused, file:checklists/005-browser-engine.md, doc:docs/adr/0012-extensions.md
- [x] **FEAT-030** Drag & drop in sidebar (tabs, folders, splits; reorder, pin/unpin, into folders, to Favorites; links from pages open as tabs); folder rename/delete — P0 · owner: nera · evidence: test:BrowserCoreTests/reorderWithinTodayAndPinByDropping, test:BrowserCoreTests/foldersAcceptTabsButNeverThemselves, test:BrowserCoreTests/foldersCanBeRenamedAndDeletedKeepingTheirTabs
- [x] **FEAT-031** Favicons (engine-delivered PNG, per-site cache for unloaded tabs, never cached from private pages) — P0 · owner: nera · evidence: test:PageLifecycleTests/iconsFromPrivatePagesAreNeverCached, test:StorageTests/iconsSurviveARelaunchAndHostsAreSanitized, test:WebKitEngineTests/candidatesPreferRasterIconsAndFallBackToFaviconICO
- [x] **FEAT-032** Find in page (⌘F, ⌘G/⇧⌘G, "2 of 5" on Chromium), zoom (⌘=/⌘−/⌘0, remembered per site per profile) — P0 · owner: nera · evidence: test:PageLifecycleTests/rememberedZoomIsAppliedWhenThePageChangesSite, test:BrowserCoreTests/zoomIsRememberedPerHostAndClamped, file:checklists/005-browser-engine.md
- [x] **FEAT-033** Private windows UI (⇧⌘N, one ephemeral session per window ended on close, no history/bookmarks/icon cache on disk, menus follow the focused window) — P0 · owner: nera · evidence: test:PageLifecycleTests/everyPageUsesTheWindowsSessionAndClosingEndsIt, test:NeraUITests/testPrivateWindowKeepsItsOwnTabs
- [ ] **FEAT-034** Space theme editor; Arc theme/profile mapping in the importer — P1 · owner: nera · evidence: planned: roadmap
- [ ] **FEAT-035** Content blocker — P1 · owner: nera · evidence: planned: roadmap

## Signature features

- [x] **FEAT-040** Peek: links a Favorite or pinned tab opens float over the page; ⌘O keeps one as a tab (same live page), Esc closes — P1 · owner: nera · evidence: test:BrowserShellTests/linksFromPinnedTabsOpenInPeekAndCanBecomeTabs, test:BrowserShellTests/peekClosesWithoutATraceAndRespectsTheSetting
- [x] **FEAT-041** Little Window for links from other apps (default; Settings › Links), "Open in Nera" moves the live page into the browser — P1 · owner: nera · evidence: test:BrowserShellTests/linksFromOtherAppsOpenInALittleWindowThatCanMoveIntoTheBrowser, test:BrowserShellTests/closingALittleWindowDiscardsItsPage
- [ ] **FEAT-042** Picture-in-Picture, auto PiP for meetings, sidebar media controls — P1 · owner: nera · evidence: test:BrowserShellTests/miniPlayerShowsABackgroundTabPlayingSound, planned: Picture-in-Picture (Chromium needs a user gesture the embedded engine can't give yet)
- [ ] **FEAT-043** Workspaces / Shared Spaces (end-to-end encrypted) — P1 · owner: nera · evidence: planned: roadmap
- [x] **FEAT-044** Site styles: per-site colors, font, hide parts of a page, custom CSS (no page-run JS), live editor — P2 · owner: nera · evidence: test:BrowserShellTests/siteStylesRestyleEveryPageOfTheirSite, test:BrowserShellTests/zapAddsWhatWasPickedToTheSiteStyle, test:BrowserCoreTests/siteStyleStyleSheets
- [x] **FEAT-047** Link rules: links from other apps that match a site (or site and path) open in a chosen Space — P1 · owner: nera · evidence: test:BrowserCoreTests/rulesMatchTheSiteItsSubdomainsAndPathPrefixes, test:BrowserShellTests/linkRulesSendMatchingLinksToTheirSpace
- [x] **FEAT-048** ⌘1–9 jump to Favorites then pinned tabs (⌘9 = last) — P1 · owner: nera · evidence: test:BrowserShellTests/commandNumberJumpsToFavoritesThenPinnedTabs
- [x] **FEAT-049** Switch without signing in again: website sign-ins (cookies) from Chromium browsers; saved passwords moved to Apple Passwords (no Nera copy) — P0 · owner: nera · evidence: test:BrowserDataTests/decryptsUnexpiredCookies, test:BrowserDataTests/savedPasswordsBecomeAnApplePasswordsCSV
- [ ] **FEAT-045** Intelligence: tab tidy, page summary, ask-the-page (on-device first) — P1 · owner: nera · evidence: planned: roadmap
- [ ] **FEAT-046** Live folders / plugin API — P2 · owner: nera · evidence: planned: roadmap

## Deliberately not built

Third-party telemetry SDKs, a mandatory vendor account, vendor-hosted sync of readable data.
