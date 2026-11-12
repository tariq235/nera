# Changelog

All notable changes to Nera are listed here, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

## Unreleased

## 0.1.8 — 2026-11-12

- **Drag Favorites and Spaces:** drag a Favorite to reorder it, drop a tab on a Favorite to make it one at that place,
  or drag a Favorite back into the sidebar. Drag a Space's icon at the bottom to reorder Spaces; drop a tab on a
  Space's icon to move it there.
- **Drag a tab out of the window** to open it in a window of its own, where you drop it.
- **Hard Reload (⇧⌘R):** reloads the page and everything on it from the network, skipping the cache.

## 0.1.7 — 2026-11-12

- **Videos pop out when you leave their tab:** a video playing with sound keeps playing in a floating window
  (Picture in Picture) while you're on another tab, and goes back into its page, still playing, when you return.
  Turn it off in Settings › General › Videos.
- **Mute from the sidebar:** a tab playing sound shows a speaker; click it to mute or unmute (Favorites too). A muted
  tab stays muted when it reloads or Nera restarts.
- **Your windows come back:** the browser windows open when you quit Nera open again next time, each on its Space
  and tab, where it was on screen. Private windows never come back.

### Fixed

- Nera didn't notice tabs playing sound, so the player for a tab playing in the background never showed, and Mute in
  the tab menu didn't work on sites shown with WebKit.

## 0.1.6 — 2026-11-11

- **⌘Z brings back what you closed:** the last closed tab, or the Today tabs Clear removed, folders and all. Typing
  in a field (in Nera or on a page), ⌘Z undoes the typing as usual.
- **Fold pinned tabs away:** click the Space's name; the pinned tab you're on stays in view. Click again to show them.
- **Site controls, like Arc's:** Copy Link and the site controls are at the right of the address. The controls hold
  Share, Customize Page, Capture and Print; your extensions; this site's permissions, developer tools and engine; and
  whether the connection is secure.
- **The File menu, like Arc's:** Blank Window (⌃⌘N), New Little Window (⌥⌘N), Share…, Capture… (⇧⌘2: drag over
  the page, or click for all of it), Capture Full Page, Save Page As (⇧⌘S) and Print (⌘P). Captures are copied and
  saved to Downloads. Add Split View is ⌃⇧=, as in Arc.
- **Updates, like Arc's:** when an update is ready, the card shows Automatic Updates and Restart and Update.
  Check for Updates… now always finds the newest version (it used to wait for the gradual rollout).

## 0.1.5 — 2026-11-10

- **Your Arc colors:** Spaces imported from Arc keep their exact colors, and the highlight in the command bar is the
  same soft tone of your Space's color as in Arc. Imported before? Right-click a Space › Use Colors from Arc.
- **Command bar, like Arc's:** the same size and place (centered on the window), an opaque panel with a deeper
  shadow, the completed address shown selected, and the highlighted suggestion with its site icon on a white tile.
  Pages of one site show their addresses, so they're easy to tell apart, and repeated suggestions are gone.
- **Favorites and pinned tabs stay put:** a link to another site opens in Peek over the page, like Arc, and the
  Favorite's tile shows that site's icon in its corner; links within the site open as usual. (Before, following a
  link from X to another site replaced the Favorite with that site.)
- **Peek, like Arc's:** the page at nearly full height over a wash of your Space's color, with Close, Open as Tab and
  Split View beside it; the address shows the Peek page's site.
- **The tab menu, like Arc's:** Copy Link, Share, Change Icon… (an emoji), Rename…, Mute, Customize Page…, Edit
  Pinned Page (use the current page, or go back), Add Split View (Favorites too), Duplicate, Move to (Favorites or
  a Space), Close Tab, and Remove Favorite.
- **Fixed:** ⌘W after opening a page from the command bar went to the pinned tab above it instead of back to the tab
  you were on.
- **Fixed:** sites' icons were missing in the command bar when the address had no "www." (facebook.com).
- **Fixed:** the page could disappear after a Space's colors changed.

## 0.1.4 — 2026-11-09

- **Video full screen:** YouTube, X and other videos now fill the whole screen; Esc returns to the window. Move the
  pointer to the left edge and the sidebar slides in, with an Exit Full Screen button (on X too).
- **Fixed:** X's videos could turn white in full screen, and the page stayed black after leaving it.
- **Fixed:** closing a tab that's playing sound now silences it at once (on X it played on for 2–3 seconds).
- **Command bar:** typing completes the site's address in place (you → youtube.com); Return opens it, → or Tab
  takes the completion. Results come in the order you'd expect: the site, the search, this Space's tabs, history,
  then tabs in other Spaces. A lighter, frosted look.
- **Fixed:** Nera could open without a window after being force-quit.
- **Fixed:** double-clicking the empty strip above the start page didn't zoom the window.

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
