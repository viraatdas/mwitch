# Changelog

All notable changes to mwitch are documented here. The same history is published at
[mwitch.viraat.dev/changelog](https://mwitch.viraat.dev/changelog).

## 1.0.1 — 2026-08-11

mwitch is out of alpha. First stable release.

- Switching to a window no longer disturbs your other display: mwitch now raises
  only the window you picked, instead of first fronting the app's previous key
  window (which could pop a stale window over whatever you had on the other screen).
- Hardened filtering of native tab surfaces (Ghostty, Terminal): background tabs
  are told apart from real windows by WindowServer Space membership instead of a
  frame heuristic, so two same-sized windows no longer collapse into one row.
- True per-window most-recently-used ordering, with active-window recency seeded
  at startup so the list is correct from the first Cmd+Tab.
- Includes everything from 0.3.7, which was tagged but never shipped.

## 0.3.7 — 2026-06-23

Tagged but never published — the release pipeline failed at Apple notarization.
Its changes shipped in 1.0.1.

- Fixed per-window recency tracking for apps that only report app-level
  Accessibility events, so the most-recently-used order stays accurate.

## 0.3.6 — 2026-06-17

- The switcher now lists windows in most-recently-used order instead of
  app z-order, matching how you actually jump between windows.

## 0.3.5 — 2026-06-15

- Detect windows on other Spaces that Accessibility can't map (e.g. Discord),
  so they show up in the switcher again.

## 0.3.4 — 2026-06-12

- Fixed switching to windows of hidden apps.

## 0.3.3 — 2026-06-09

- Esc now cancels the switcher on every install: cancel is handled from the
  global event tap instead of the panel.

## 0.3.2 — 2026-06-03

- Show windows whose window-list title is empty (e.g. Contacts).
- The update check now shows the version only, without the build number.
- Site: copy button for the Homebrew install command.

## 0.3.1 — 2026-05-31

- Clearer message when an update check finds no new version.
- Moved developer notes out of the README.

## 0.3.0 — 2026-05-31

- Simplified the status menu: removed the Show Switcher, Accessibility Settings,
  and Screen Recording Settings items.

## 0.2.2 — 2026-05-31

- Rewrote the switcher panel in SwiftUI and separated UI presentation from
  session state.
- Fixed a commit-gating bug where releasing unrelated modifiers could commit
  the switch.

## 0.2.1 — 2026-05-30

- First public release: downloads published via GitHub Releases.
- Sparkle auto-update.
- Search results ranked by match quality, with a fix for a search/selection
  state conflict.
- Windows matched by CGWindowID so switching works in Chrome.
