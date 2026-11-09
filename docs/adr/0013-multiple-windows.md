# ADR-0013: Multiple browser windows (⌘N)

**Status:** accepted (2026-11-09) · **Deciders:** maintainer

## Context

⌘N opens a second browser window in every Mac browser. In Nera it does nothing: the app has one `AppModel`, which
is both the app-wide coordinator (library, pages, history, downloads, extensions, engine events) and the state of
the one window (selected Space and tab, sidebar, command bar, find bar, Peek, the page prompt being shown). Two
windows on that model would share one selection and fight over the same page views.

What people expect (the behaviour Nera matches, with its own look): every window shows the same Spaces, pinned tabs,
Today and Favorites; each window has its own selected Space and tab, sidebar, command bar and Peek; ⌘N opens a
window with the command bar ready; closing a window closes nothing in the library.

## Decision

Split the model in two:

- **`AppModel` (one per app):** the library store, pages, history, favicons, downloads, extensions, updates, Safe
  Browsing, and engine events. Unchanged API for everything that isn't per window.
- **`BrowserWindow` (one per window, `@Observable`):** selected Space and tab, sidebar visible/peeking/width, command
  bar, find bar, zoom indicator, Peek, page swipe, editing sheets. Views get it from the environment.

The library's persisted selection is the last focused window's. Actions sent from a window apply that window's
selection first (`window.send(_:)` wraps `AppModel.send`), so the reducer stays as it is: only the window being used
sends actions.

**Pages:** one page per tab, as today. A page's view lives in one window at a time; if two windows select the same
tab, the window being used shows it and the other shows "Showing in another window", with a click to bring it back.

**Page prompts** (dialogs, permissions, downloads, certificate errors): shown in the window that shows the page; if
no window does, in the last focused window.

**Private windows** keep their own `AppModel` (separate library and session), with one `BrowserWindow`.

## Consequences

- One mechanical migration: views read window state from `BrowserWindow` instead of `AppModel`. Done in steps,
  each step building and passing the full test suite.
- New tests: two windows select different tabs; closing a tab selected in another window; a prompt for a page
  shown in the other window; ⌘N opens a window with the command bar; quitting with two windows restores both.
- Window restoration (which windows were open, each one's Space) is part of this work.
