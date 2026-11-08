# Resilience

How Nera keeps working, and keeps the user's library, when things go wrong.

## Crash-loop safe mode (SEC-054)

`Storage.LaunchGuard` keeps `launch.json` next to the library: `{launching, failedLaunches}`.

- **At launch** (`BrowserShell.LaunchSafety.isSafeMode`, read before Chromium starts): if the previous launch
  never completed, `failedLaunches` goes up by one. After **2** failed launches in a row, this launch runs in
  safe mode.
- **A launch succeeds** after 10 seconds of running, or on a clean quit. The record then resets.
- **Safe mode:**
  - Chromium isn't started, so the WebKit fallback runs.
  - No tab is selected, so no page loads until the user picks one.
  - A banner explains why and how to leave: quit and reopen. The safe-mode run counts as a success after 10 s.
- **Test runs** (`NERA_UI_TEST`, `--engine-self-test`) never read or write the record.

Verified by hand on 2026-10-27: a faked record of `{launching: true, failedLaunches: 1}` gave safe mode, with no
Chromium helper processes and the banner shown. The record reset after 10 s.

## Library schema migrations

`JSONFileStore` stores `{schemaVersion, state}`.

- **Older file:** it's copied to `library.v<n>.json` once, then every `LibraryMigration` step from `n` up to the
  current version runs in order. The steps rewrite the decoded JSON, never today's Swift types.
- **Missing step:** loading fails with `missingMigration` and the file is left untouched.
- **Newer file:** loading is refused (`newerSchema`) rather than downgrading the file.
- **Unreadable file:** it's moved to `library.corrupt-<time>.json`, never deleted.

Rule: bump `JSONFileStore.schemaVersion` only together with a migration step and a fixture in
`Tests/StorageTests/Fixtures` written by the previous release. `everyShippedVersionHasAStep` enforces the step.

## Window and Space restoration (MAC-005)

- **Window frames** are restored by SwiftUI's `WindowGroup` (macOS state restoration).
- **Sidebar width** is fixed at 260 pt, so there's nothing to restore.
- **The focused Space, the selected tab and the Space order** live in the library and survive a relaunch
  (`focusedSpaceAndTabSurviveARelaunch`).

## Fuzz and stress tests (SEC-067, PERF-009)

The tests are seeded and deterministic (`TestSupport.SeededRandom`): a failure message names its seed, so it
always reproduces. They run on every PR in a few seconds.

| Target | Test | Property |
|---|---|---|
| Omnibox | `randomInputNeverEscapesTheSearchEngine` | Any input is blank, a URL, or a search on the configured engine |
| Navigation policy | `pagesNeverReachDangerousSchemes` | Pages can't open `javascript:`/`vbscript:`/`file:`; only clicks can open other apps; upgrades are always HTTPS |
| Arc importer | `damagedSidebarFilesParseOrFailCleanly` | Damaged files parse or throw, never crash |
| Library decode | `damagedLibrariesLoadOrAreMovedAside` | Damaged libraries load or are kept aside, never crash or vanish |
| Reducer | `randomActionSequencesKeepTheLibraryConsistent` | The selection always exists; no tab appears twice |
| 500 tabs / 50 Spaces | `fiveHundredTabsAcrossFiftySpaces` | Build, 5,000 switches and save/load stay within budget |

Longer fuzzing (libFuzzer on Linux, hours per target) is a planned addition to the nightly runs.

## Accessibility audit (A11Y-003)

`SmokeTests.testAccessibilityAuditOnMainScreens` runs Xcode's `performAccessibilityAudit()` on three screens:
the empty window, the open command bar and a loaded page.

It fixed four product bugs on its first run:
- the sidebar's "+" menu had no label;
- the command-bar field had no label;
- the empty-state tip had too little contrast on tinted Space themes;
- content behind the command bar was still exposed to VoiceOver (the bar is now modal).

Only framework artifacts are ignored:
- issues without an element;
- the window's full-size content group, which AppKit creates outside SwiftUI;
- "action missing" on SwiftUI menu buttons, which open with AXShowMenu;
- anything in the title-bar strip (the system's window buttons).
