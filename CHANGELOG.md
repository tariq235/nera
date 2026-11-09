# Changelog

All notable changes to Nera are listed here, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

## Unreleased

## 0.1.4 — 2026-11-09

- **Video full screen:** YouTube, X and other videos now fill the whole screen; Esc returns to the window. Move the
  pointer to the left edge and the sidebar slides in, with an Exit Full Screen button (on X too).
- **Fixed:** X's videos could turn white in full screen, and the page stayed black after leaving it.
- **Command bar:** typing completes the site's address in place (you → youtube.com); Return opens it, → or Tab
  takes the completion. Results come in the order you'd expect: the site, the search, this Space's tabs, history,
  then tabs in other Spaces. A lighter, frosted look.
- **Fixed:** Nera could open without a window after being force-quit.

## 0.1.3 — 2026-11-09

- **Move between tabs from the keyboard:** ⇧⌘] / ⇧⌘[, ⌥⌘↓ / ⌥⌘↑ and ⌃Tab / ⌃⇧Tab.
- **Tab menu:** Rename… (your name stays while the page title changes), Duplicate, and Move to Space.
- **Updates in the sidebar:** when a new version is ready, a card at the bottom of the sidebar says so; click it to
  restart into the new version. After updating, a card shows what's new.

## 0.1.2 — 2026-11-09

- **New window (⌘N):** another browser window with the same Spaces, pinned tabs and Favorites, its own Space
  and tab, and the command bar ready.
- **Command bar (⌘T, ⌘L):** appears at once over the page; your open tabs before you type, with site icons and
  "Switch to Tab"; the highlight takes the Space's color. Esc or a click anywhere else closes it, and the
  sidebar stays usable (switch Spaces with a two-finger swipe).
- **⌘W** closes what's in front: the command bar, otherwise the tab. It never closes the main window.
- **Private windows (⇧⌘N):** open at once over your window at its full size, with the command bar ready; one
  list of private tabs; ⌘W closes an empty one.
- **Appearance:** follows your Mac's light or dark setting. Settings › General › Appearance chooses Light, Dark
  or each Space's own.
- **Right-click a Space** to change its icon, name or theme color, its profile, add a folder or delete it.
- Faster sidebar slide (⌘S).

## 0.1.1 — 2026-11-08

- Pages are no longer drawn shifted after showing or hiding the sidebar: the top of the page was cut off and
  clicks landed above where they were aimed.
- Hiding the sidebar now gives the page the whole window, inside a thin frame; the window's buttons and the
  sidebar come back when you move the pointer to the left edge.
- ⌘S slides the sidebar in and out together with the page, in one smooth motion.
- Drag the sidebar's edge to make it wider or narrower (VoiceOver: "Sidebar width", adjustable).
- Double-clicking the empty strip above the page zooms the window again, like any Mac title bar.
- Videos on X play: X and Twitter open with WebKit (X serves only H.264, which Nera's Chromium can't play yet),
  and the "this site's video needs WebKit" suggestion now also appears on sites that stream video.

## 0.1.0 — 2026-11-08

The first public release: an early beta for macOS 14 or later on Apple silicon.

- Vertical tabs, Spaces, Favorites and pinned tabs, folders.
- Command bar (⌘T, ⌘L) with open-tab search; Split View; Peek and Little Windows.
- Chromium (Chromium Embedded Framework 156) by default, with WebKit per site for sites that need it.
- Import from Chrome, Safari, Firefox, Edge, Brave and Arc: bookmarks, history and sign-ins.
- Chrome extensions (Manifest V3).
- HTTPS-Only by default, phishing and malware warnings (Google Safe Browsing), per-site permissions, download safety.
- No telemetry. Signed and notarized; signed updates you can turn off in Settings › General.
