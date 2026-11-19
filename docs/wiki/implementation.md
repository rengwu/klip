---
title: Implementation and validation
updated: 2026-11-19
order: 2
---

# Implementation and validation

Version 0.1.0 is built to the [plan](plan.md). The project is not under version control, so there is no revision to cite; this page describes the files as they stood on 2026-11-15.

## Build and run

Requires Xcode Command Line Tools; full Xcode is not needed.

```sh
swift run KlipCoreTests   # core tests
./build.sh                # universal, ad-hoc-signed build/Klip.app
```

Data lives in `~/Library/Application Support/Klip/`: `config.json`, `history.sqlite`, and `images/`. Setting `KLIP_HOME` points a run at another directory. `KLIP_SHOW=panel` or `KLIP_SHOW=settings` opens that window at launch, for checking a build without the global shortcut.

## Structure

| Part | Role |
| --- | --- |
| `Sources/KlipCore/Store.swift` | History in SQLite through the system `libsqlite3`; image payloads as PNG files. Duplicates, search, paging, decay, size eviction. |
| `Sources/KlipCore/AppConfig.swift` | Settings and their defaults, stored as JSON. |
| `Sources/KlipCore/Model.swift` | Item kinds, captures, row titles. |
| `Sources/Klip/Clipboard.swift` | Reads copies from the pasteboard, writes items back, sends ⌘V. |
| `Sources/Klip/HotKeyCenter.swift` | The global shortcut through Carbon hot keys. |
| `Sources/Klip/PanelController.swift` | The panel: search field, list, key handling, paging. |
| `Sources/Klip/SettingsWindowController.swift` | The Settings window. |
| `Sources/Klip/AppDelegate.swift` | Wiring, the pasteboard poll, the menu bar item. |

KlipCore has no AppKit dependency. There are no third-party packages.

## How it works

- The pasteboard has no change notification, so Klip compares its change count every 0.4 s.
- The panel is a non-activating `NSPanel`. It takes the keyboard without making Klip the active app, so the app the user was in stays frontmost and receives the paste.
- The list loads 50 items, and the next 50 when the scroll position or the highlight nears the end.
- Search lowercases both sides in Swift and matches with SQLite `instr`, because SQLite's `LIKE` ignores case only for ASCII.
- A repeated copy is recognized by a SHA-256 of its kind and content. Formatting is not part of identity: the newest copy decides whether an item carries it.
- Decay and the size limit are applied after every save, every five minutes, and when a setting changes.

## Validation

Tested on macOS 27.0 (arm64), Swift 6.4.2, against an isolated `KLIP_HOME`.

**Core tests:** `swift run KlipCoreTests` passed, 47 of 47. They cover ordering, repeated copies, paging, search (case, non-ASCII, literal wildcards, file paths, images), titles, formatting replacement, decay with pins, eviction order, the 10% item cap, image files, delete, clear, persistence across reopen, and settings defaults and round-trip.

**Built app, observed:**

| Scenario | Result |
| --- | --- |
| `./build.sh` produces a signed universal app | Passed: `x86_64 arm64`, signature verified |
| Text copies are captured | Passed |
| Copying the same text again moves it to the top, without a second row | Passed |
| A PNG image is captured with its dimensions and a file under `images/` | Passed |
| A copy marked `org.nspasteboard.ConcealedType` is skipped | Passed |
| One file and two files copied are stored as paths | Passed |
| Text with RTF is stored as rich text with its RTF | Passed |
| The panel shows rows aligned across kinds, pins, ⌘1–⌘9, the footer | Passed: [screenshot](attachments/2026-11-15-panel.png) |
| The panel updates while open as new copies arrive | Passed |
| Settings shows every control, and the Accessibility row while permission is missing | Passed: [screenshot](attachments/2026-11-15-settings.png) |

![The panel with files, rich text, an image, and pinned items](attachments/2026-11-15-panel.png)

![The Settings window](attachments/2026-11-15-settings.png)

**Untested.** The agent could not send keystrokes to the app: the terminal lacks the Accessibility permission. These need a person at the keyboard:

- The global shortcut opening and closing the panel
- Typing in the search field, ↑ ↓, Return, Esc, clicking a row
- ⌘P, ⇧⌘P, ⌘⌫, ⌘1–⌘9, ⌘,
- Pasting into the previous app once Accessibility is granted
- Loading further pages while scrolling past 50 items
- Recording a new shortcut, launch at login, hiding the menu bar icon, Clear History
- Appearance in light mode, and on a second display

## Icon

The first icon was a clipboard character with a face, chosen from [four directions](journal/2026-11-15-grill-10db2c85deb2f154ccc00ce2e9b27e8b.md). On 2026-11-19 the user asked for a logo with no eyes and no personified characters. The [redesign rounds](journal/2026-11-19-grill-icon-redesign.md) went through two stages:

1. The face was refined away, and the result shipped in orange in 0.3.0.
2. The user then chose a monochrome version as the definitive logo: “make this the new definitive logo. no more orange.”

The logo is the Clear version:

- **Tile:** a dark graphite squircle in Apple's icon shape, with straight sides, continuous corners, a light rim and a soft glow at the top.
- **Board:** frosted glass, tilted slightly, with a visible edge so it looks thick.
- **Clip:** solid white. A plate grips the board's top edge and rises through curved corners into an arched tab. The hole in the tab shows the tile behind.
- **Text:** four lines in translucent white, broken into words. The second line is solid white, marking the selected item.

The menu bar glyph is a template image, so it was already monochrome. It matches the logo: the tilted board outline, the clip silhouette with its hole, and three lines of text getting shorter.

The SVG filters are set to `color-interpolation-filters="sRGB"`. In the default linearRGB, 8-bit precision runs out in dark greys, and the drop shadow turned the tile's gradient into visible steps.

The website is a separate project, `klip-site`. It uses a 256 px export of this icon as its logo and favicon, and its Download button is off-white (`#f6f6f5`) instead of orange.

- `Resources/AppIcon.svg` is the artwork. `Resources/make-icon.sh` renders it with a headless Chromium-based browser and builds `Resources/AppIcon.icns`, which is committed so `build.sh` needs no renderer.
- `Sources/Klip/StatusIcon.swift` draws the menu bar glyph in code as a template image.

![The app icon](attachments/2026-11-19-app-icon-monochrome.png)

![The menu bar glyph, enlarged and at 18 and 36 pt, on light and dark](attachments/2026-11-19-menu-bar-glyph.png)

Checked:

- The `.icns` renders as approved and still reads at 16 px.
- The tile's gradient has no steps; this was measured row by row.
- The glyph drawn by `StatusIcon.swift` matches the approved preview at the same size.
- The built bundle contains the new `.icns`.
- The site, rendered locally, shows the new logo and the white button.

Not yet looked at by the agent: the glyph in the real menu bar and the icon in Finder. Finder may show the old icon until its icon cache refreshes.

## Limits

- The build is ad-hoc signed. An ad-hoc signature is identified by its code hash, so at first every rebuild orphaned the Accessibility grant: System Settings still listed Klip as allowed while the new build was refused. `build.sh` now signs with the designated requirement `identifier "local.klip"` so the grant should follow the bundle identifier across rebuilds. That it survives a rebuild is not yet confirmed. A stale entry is cleared with `tccutil reset Accessibility local.klip`.
- History is stored unencrypted.
- A file reference is a path; it goes stale if the file moves.
- Images are written back as PNG only.
