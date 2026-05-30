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

## Install

### Homebrew

```sh
brew tap viraatdas/mwitch https://github.com/viraatdas/mwitch
brew install --cask mwitch
```

The cask installs the signed, notarized zip from GitHub Releases. Sparkle keeps the app updated automatically in the background; `brew upgrade --cask mwitch` also follows the release-pinned cask after each tagged release.

### Direct download

Download the latest release zip:

```sh
open https://github.com/viraatdas/mwitch/releases/latest/download/mwitch.zip
```

Unzip it and drag `mwitch.app` into `/Applications`.

## Build

Requirements for building from source:

- Xcode command-line tools (`xcode-select --install`)
- Swift 5.9+


```sh
./build.sh
open build/mwitch.app
```

The script does a release build for `arm64` only, assembles `build/mwitch.app`, embeds + re-signs `Sparkle.framework` (for auto-update), stamps the version, and signs the bundle (Developer ID if available, else ad-hoc). The mwitch binary itself is ~180 KB; the embedded Sparkle framework brings the bundle to ~2 MB.

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

## Auto-update

mwitch ships with [Sparkle](https://sparkle-project.org). Installed copies silently check `https://mwitch.viraat.dev/appcast.xml` once a day, then download and install new versions in place — no manual re-download. Each release is signed with an EdDSA key, and the public half is pinned in the app's `Info.plist` (`SUPublicEDKey`). There's also a "Check for Updates…" item in the menu-bar menu.

## Releasing

### Automated (tag → ship)

Push a version tag and GitHub Actions does everything — build, sign, notarize, publish the GitHub Release zip, EdDSA-sign the appcast, deploy the website, and update the Homebrew cask SHA:

```sh
git tag v0.2.1 && git push origin v0.2.1
```

The workflow (`.github/workflows/release.yml`) runs on a macOS runner: it derives the marketing version from the tag (`v0.2.1` → `0.2.1`), the build number from the commit count, then runs `build.sh` + `notarize.sh` and deploys `mwitch-site` to Vercel production. You can also trigger it manually from the Actions tab (it takes a version input). Installed copies (0.2.0+) auto-update within a day.

**Required GitHub secrets** (Settings → Secrets and variables → Actions):

| Secret | What it is / how to get it |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Your "Developer ID Application" cert exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `SPARKLE_PRIVATE_KEY` | Export the **existing** EdDSA key: run `generate_keys -x key.txt` (find it under `.build/artifacts/sparkle/Sparkle/bin/`), approve the keychain prompt, paste the file contents. Must be the same key already pinned in `Info.plist`. |
| `AC_API_KEY_P8` | App Store Connect API key (`.p8`, Developer → Integrations → keys with "Developer" access), `base64`-encoded |
| `AC_API_KEY_ID` | The API key's Key ID |
| `AC_API_ISSUER_ID` | The App Store Connect issuer ID |
| `VERCEL_TOKEN` | A Vercel access token (vercel.com → Settings → Tokens) |

> Security note: these secrets let CI sign and ship code to every user's Mac. If they leak, an attacker could push a malicious auto-update. Keep repo access tight; rotate the API key / Vercel token if ever exposed.

### Manual (local fallback)

1. Bump `VERSION` (e.g. `0.2.0` → `0.2.1`).
2. **Commit the bump** — the build number is the git commit count, so the commit advances it, and Sparkle uses `CFBundleVersion` to decide an update is newer. Building on an uncommitted tree reuses the current count and Sparkle won't offer the update.
3. `./build.sh` — build, embed + sign Sparkle, stamp the version, sign with Developer ID.
4. `./notarize.sh` — notarize + staple, regenerate the EdDSA-signed `appcast.xml`, stage it + `mwitch.zip` into `mwitch-site/`.
5. `cd mwitch-site && vercel deploy --prod --yes`.

**Back up the EdDSA key.** It lives only in your login keychain (Keychain Access → "Private key for signing Sparkle updates", or `generate_keys -x`). Lose it and you can never sign an update the installed base will accept — auto-update breaks permanently for existing users.

## Architecture

```
Sources/mwitch/
  main.swift             entry point — NSApplication.accessory mode
  AppDelegate.swift      menu-bar item, accessibility prompt, hotkey wiring, Sparkle updater
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
| Silent auto-update | Sparkle `SPUStandardUpdaterController` + hosted EdDSA-signed appcast |

## Known limitations

- Windows on other Spaces are still listed (CGWindowList shows them); activating them will switch Spaces.
- Minimized windows are listed and un-minimized on activation.
- Fullscreen Spaces work, but the panel may appear briefly behind a system Mission Control animation. Just press Cmd+Tab again.
- No drag-to-reorder, no per-app grouping, no preview thumbnails — by design (window switching only).

## License

MIT. See `LICENSE`.
