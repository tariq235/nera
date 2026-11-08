# Changelog

All notable changes to Nera are listed here, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

## Unreleased

- Pages are no longer drawn shifted after showing or hiding the sidebar: the top of the page was cut off and
  clicks landed above where they were aimed.
- Hiding the sidebar now gives the page the whole window, inside a thin frame; the window's buttons and the
  sidebar come back when you move the pointer to the left edge.
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
