# 003 — Accessibility

Target: everything usable with VoiceOver, keyboard only, Switch Control, at the largest Dynamic Type size, and in Increase Contrast / Reduce Motion modes.

- [x] **A11Y-001** Sidebar tab rows expose their title as the accessibility label — P0 · owner: nera · evidence: test:NeraUITests/testOpenCloseRestoreTab
- [x] **A11Y-002** Core flows work keyboard-only (⌘T, ⌘W, ⇧⌘T, ⌘D) — P0 · owner: nera · evidence: test:NeraUITests/testOpenCloseRestoreTab, test:NeraUITests/testPinnedTabSurvivesClose
- [x] **A11Y-003** `performAccessibilityAudit()` passes on every main screen in UI tests — P0 · owner: nera · evidence: test:NeraUITests/testAccessibilityAuditOnMainScreens
- [x] **A11Y-004** Full keyboard navigation of the sidebar (arrow keys move between tabs, Return goes into the page, Space opens or closes the tab's folder) — P0 · owner: nera · evidence: test:BrowserCoreTests/spaceOnTheKeyboardFindsTheSelectedTabsFolder, file:Packages/NeraKit/Sources/Sidebar/SidebarView.swift
- [x] **A11Y-005** Command bar suggestions announced by VoiceOver: each row is one labelled button (the highlighted one selected), arrow keys announce the row and its position, a new list is announced when typing pauses — P0 · owner: nera · evidence: test:BrowserShellTests/movingTheHighlightAnnouncesTheRowAndItsPosition, test:BrowserShellTests/aNewListIsAnnouncedWithWhatReturnOpens, test:NeraUITests/testCommandBarSuggestionsAreAccessible, file:Packages/NeraKit/Sources/CommandBar/SuggestionSpeech.swift
- [ ] **A11Y-006** Dynamic Type up to accessibility sizes (iOS) without clipping — P0 · owner: nera · evidence: planned: later
- [ ] **A11Y-007** Reduce Motion disables decorative animations — P1 · owner: nera · evidence: planned: later
- [ ] **A11Y-008** Increase Contrast / Differentiate Without Color respected in themes — P1 · owner: nera · evidence: planned: later
- [x] **A11Y-009** Web content accessibility tree exposed by both engines (VoiceOver reads pages): WebKit always; Chromium when it starts with accessibility (VoiceOver or Switch Control on, or Settings › General › Accessibility), and an assistive app appearing mid-session is remembered and offered a restart — P0 · owner: nera · evidence: ci:scripts/a11y/check-screen-readers.sh, test:BrowserShellTests/anAssistiveAppAppearingOffersARestart, test:NeraUITests/testScreenReadersCanReadPages, file:Packages/NeraKit/Sources/BrowserShell/WebAccessibility.swift
- [x] **A11Y-010** Every icon-only button has a label and tooltip (enforced: an icon-only button without `.accessibilityLabel` or `.help` fails CI) — P0 · owner: nera · evidence: ci:scripts/ci/check-a11y-labels.py
- [ ] **A11Y-011** Snapshot tests at large text sizes, light/dark, high contrast — P1 · owner: nera · evidence: planned: later
- [x] **A11Y-012** Page content behind a prompt (dialog, permission, sign-in) is hidden from assistive technologies, like any modal; prevents VoiceOver hanging on a page blocked in `alert()` — P0 · owner: nera · evidence: test:NeraUITests/testAlertIsShownWithItsOriginAndPageContinues, file:Packages/NeraKit/Sources/BrowserShell/WebViewHost.swift
