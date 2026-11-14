# Klip

A simple clipboard manager for macOS, built in native Swift and AppKit.

- Keeps text, rich text, images and file references
- ⇧⌘V opens a searchable panel; Return pastes into the app you were in
- ⌘1–⌘9 paste directly, ⌘P pins, ⇧⌘P shows pinned items only, ⌘⌫ deletes
- History decays after 7 days (configurable up to 30) and is capped at 500 MB (configurable)
- Skips copies that password managers mark as concealed

## Build

Requires Xcode Command Line Tools and macOS 13+.

```sh
swift run KlipCoreTests   # tests
./build.sh                # build/Klip.app
```

Move `build/Klip.app` to `/Applications` and open it. Klip lives in the menu bar. To paste directly into apps, allow it under System Settings → Privacy & Security → Accessibility; without that, Return copies the item and you press ⌘V yourself.

Design decisions and validation are in [the project wiki](docs/wiki/index.md).
