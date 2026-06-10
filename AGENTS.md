# AGENTS.md

This file is for coding agents working on mwitch. Keep `README.md` customer-facing and put developer, build, release, and implementation details here.

## Project Overview

mwitch is a native macOS menu-bar app written in Swift. It replaces the default `Cmd+Tab` flow with a per-window switcher.

Core files:

- `Sources/mwitch/AppDelegate.swift`: app startup, permissions prompts, menu bar item, Sparkle updater, launch at login.
- `Sources/mwitch/HotkeyManager.swift`: global `Cmd+Tab`, `Cmd+Shift+Tab`, Cmd-release commit, and Esc cancel handling.
- `Sources/mwitch/SwitcherController.swift`: switcher session state and commit/cancel behavior.
- `Sources/mwitch/SwitcherPanel.swift`: AppKit panel shell.
- `Sources/mwitch/SwitcherPanelView.swift`: table UI and row rendering.
- `Sources/mwitch/SwitcherListState.swift`: filtered rows and absolute window selection mapping.
- `Sources/mwitch/SwitcherSearch.swift`: search ranking.
- `Sources/mwitch/WindowEnumerator.swift`: CoreGraphics window listing.
- `Sources/mwitch/WindowActivator.swift`: Accessibility window activation.

## Local Commands

Run tests:

```sh
swift test
```

Build a signed local release app:

```sh
./build.sh release
open build/mwitch.app
```

Validate release support files:

```sh
brew style Casks/mwitch.rb
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'
bash -n build.sh notarize.sh
git diff --check
```

## Release Model

Releases are the source of truth for downloads.

- GitHub Releases host `mwitch.zip`.
- `mwitch-site/appcast.xml` is committed and deployed for Sparkle.
- `mwitch-site/mwitch.zip` must not be committed.
- `/mwitch.zip` on the website redirects to `https://github.com/viraatdas/mwitch/releases/latest/download/mwitch.zip`.
- The Homebrew cask downloads the versioned release asset at `https://github.com/viraatdas/mwitch/releases/download/v#{version}/mwitch.zip`.

Versioning:

- `VERSION` contains the marketing version.
- `build.sh` stamps `CFBundleShortVersionString` from `MWITCH_VERSION` or `VERSION`.
- `build.sh` stamps `CFBundleVersion` from the git commit count. Sparkle uses this build number to decide whether an update is newer.
- Commit the version bump before building or tagging so the build number advances.

## Automated Release

Tagging a version should ship it through `.github/workflows/release.yml`:

```sh
git tag -a v0.3.1 -m "mwitch v0.3.1"
git push origin main
git push origin v0.3.1
```

The workflow:

1. Builds the app.
2. Signs with the Developer ID certificate from GitHub Actions secrets.
3. Notarizes and staples with App Store Connect API credentials.
4. Generates the EdDSA-signed Sparkle appcast.
5. Uploads `mwitch.zip` and `appcast.xml` to the GitHub Release.
6. Deploys `mwitch-site` to Vercel production.
7. Updates `Casks/mwitch.rb` and `mwitch-site/appcast.xml` on `main`.

Required GitHub Actions secrets:

- `DEVELOPER_ID_CERT_P12`
- `DEVELOPER_ID_CERT_PASSWORD`
- `SPARKLE_PRIVATE_KEY`
- `AC_API_KEY_P8`
- `AC_API_KEY_ID`
- `AC_API_ISSUER_ID`
- `VERCEL_TOKEN`

These secrets can sign and ship code to users. Do not print them, commit them, or paste them into issue comments.

## Manual Release Fallback

Use this only if Actions is unavailable.

```sh
./build.sh release
MWITCH_DOWNLOAD_URL_PREFIX="https://github.com/viraatdas/mwitch/releases/download/vX.Y.Z/" ./notarize.sh
gh release create vX.Y.Z build/mwitch.zip mwitch-site/appcast.xml --repo viraatdas/mwitch --title "mwitch vX.Y.Z" --notes "Signed and notarized mwitch release." --latest
```

After uploading, set the cask SHA to:

```sh
shasum -a 256 build/mwitch.zip
```

Then commit `Casks/mwitch.rb` and `mwitch-site/appcast.xml`. Do not commit `mwitch-site/mwitch.zip`.

Deploy the website:

```sh
cd mwitch-site
vercel deploy --prod --yes
```

## Sparkle Notes

Sparkle is embedded through Swift Package Manager. The app pins the public EdDSA key in `Resources/Info.plist` with `SUPublicEDKey`.

Back up the private EdDSA key. If it is lost, existing installs cannot accept future Sparkle updates signed with a new key.

## Homebrew Notes

The cask lives at `Casks/mwitch.rb`. Keep it release-based:

- `version` must match the release tag without the leading `v`.
- `sha256` must match the GitHub Release `mwitch.zip` asset.
- Run `brew style Casks/mwitch.rb` before committing cask changes.

## Repository Hygiene

- Leave unrelated local files alone, especially untracked tool state such as `.rudder/`.
- Do not commit build outputs under `build/` or `.build/`.
- Do not commit `mwitch-site/mwitch.zip`.
- Keep customer-facing documentation in `README.md` short and plain.
