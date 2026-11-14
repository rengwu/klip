#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/Klip.app"
version="${1:-$(cat "$root/VERSION")}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  echo "Invalid version: $version" >&2
  exit 1
fi

# Build each slice separately so Command Line Tools are sufficient (SwiftPM's
# multi-architecture build backend requires the full Xcode installation).
# Both slices can share one output path, so each is copied aside before the next build.
slices="$(mktemp -d)"
trap 'rm -rf "$slices"' EXIT
for architecture in arm64 x86_64; do
  swift build -c release --product Klip --arch "$architecture" --package-path "$root"
  bin_dir="$(swift build -c release --arch "$architecture" --package-path "$root" --show-bin-path)"
  cp "$bin_dir/Klip" "$slices/$architecture"
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
lipo -create "$slices/arm64" "$slices/x86_64" -output "$app/Contents/MacOS/Klip"

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Klip</string>
  <key>CFBundleDisplayName</key>     <string>Klip</string>
  <key>CFBundleIdentifier</key>      <string>local.klip</string>
  <key>CFBundleExecutable</key>      <string>Klip</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$version</string>
  <key>CFBundleVersion</key>        <string>$version</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <!-- Menu bar only: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Seal the bundle: launch at login needs a properly signed bundle.
# An ad-hoc signature is normally identified by its code hash, which changes with every
# build, so macOS would forget the Accessibility grant each time. Naming the bundle
# identifier as the requirement keeps the grant across rebuilds.
codesign --force --deep --sign - --requirements '=designated => identifier "local.klip"' "$app"
codesign --verify --deep --strict "$app"

echo "built: $app"
