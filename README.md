# mwitch

A minimal macOS window switcher inspired by the keyboard-driven flow many users associate with apps like Contexts. Cmd+Tab opens a sidebar listing **every window** on the active display — not just one icon per app — so you can jump straight to the window you want.

Built fresh in Swift using public Apple APIs (AppKit, Accessibility, Carbon HotKey, CoreGraphics window list). Apple Silicon only.

## What it does

- **Cmd+Tab** — open the switcher. The 2nd window (most-recent background window) is preselected.
- **Cmd+Tab again** — advance selection.
- **Cmd+Shift+Tab** — go backwards.
- **↑ / ↓** — move selection.
- **Type** — fuzzy filter by app name or window title.
- **Enter or release Cmd** — switch to the selected window.
- **Esc** — dismiss without switching.
- **Click a row** — switch immediately.

Each row shows the app's icon, the window title, and the app name underneath. Windows are listed front-to-back, across every running app.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 13 (Ventura) or later
- Xcode command-line tools (`xcode-select --install`)
- Swift 5.9+

## Build

```sh
./build.sh
open build/mwitch.app
```

The script does a release build for `arm64` only, assembles `build/mwitch.app`, and ad-hoc signs it. Resulting binary is ~180 KB.

For iteration:

```sh
swift build --arch arm64        # debug
.build/arm64-apple-macosx/debug/mwitch    # run from terminal to see stdout
```

## First launch — grant Accessibility

mwitch needs Accessibility permission to (a) enumerate windows across other apps and (b) raise a specific window when you select it. On first launch macOS prompts you; if you miss it:

**System Settings → Privacy & Security → Accessibility → enable `mwitch`**

Then quit and relaunch the app. (The status-bar menu has an "Open Accessibility Settings…" shortcut.)

## Cmd+Tab takeover

Registering Cmd+Tab as a global hotkey relies on the Carbon `RegisterEventHotKey` API. While mwitch is running and has Accessibility access, its handler runs instead of the system app-switcher. Quitting mwitch returns Cmd+Tab to its default behavior. There is no system-level "disable Apple's app switcher" toggle — this is how every replacement on macOS works.

## Architecture

```
Sources/mwitch/
  main.swift             entry point — NSApplication.accessory mode
  AppDelegate.swift      menu-bar item, accessibility prompt, hotkey wiring
  HotkeyManager.swift    Carbon hotkey + NSEvent flagsChanged for Cmd-release
  WindowEnumerator.swift CGWindowList → [WindowEntry], dedup + filtering
  WindowActivator.swift  AXUIElement raise + un-minimize + setMain
  SwitcherController.swift  state machine: show / advance / commit / cancel
  SwitcherPanel.swift    borderless NSPanel, right-edge sidebar, NSTableView UI
```

### Why each API

| Concern | API |
|---|---|
| Global Cmd+Tab hotkey | `RegisterEventHotKey` (Carbon) — only reliable way to grab a system shortcut |
| Detect Cmd release | `NSEvent.addGlobalMonitorForEvents(.flagsChanged)` |
| List windows across apps | `CGWindowListCopyWindowInfo` — fast, no permission needed for metadata |
| Bring a specific window forward | `AXUIElementPerformAction(kAXRaiseAction)` — needs Accessibility |
| Activate the owning app | `NSRunningApplication.activate` |
| App icons / names | `NSRunningApplication.icon / localizedName` |
| Floating UI that doesn't steal focus | `NSPanel` with `.nonactivatingPanel`, `level = .floating` |

## Known limitations

- Windows on other Spaces are still listed (CGWindowList shows them); activating them will switch Spaces.
- Minimized windows are listed and un-minimized on activation.
- Fullscreen Spaces work, but the panel may appear briefly behind a system Mission Control animation. Just press Cmd+Tab again.
- No drag-to-reorder, no per-app grouping, no preview thumbnails — by design (window switching only).

## License

MIT. See `LICENSE`.
