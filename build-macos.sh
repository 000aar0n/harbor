#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ]; then
  echo 'Build this project on macOS, or use its GitHub Actions download.' >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Apple developer tools are not installed. Use the prebuilt download.' >&2
  exit 1
fi
mkdir -p build dist
stage=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/eloter.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
iconset="$stage/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" assets/AppIcon.jpg --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -s format png -z "$retina" "$retina" assets/AppIcon.jpg --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$app/Contents/Resources/AppIcon.icns"
test -s "$app/Contents/Resources/AppIcon.icns"
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc Harbor.swift Tunnel.swift TunnelSettings.swift MouseCapture.swift \
  -O -whole-module-optimization -sdk "$sdk" -target arm64-apple-macos14.0 \
  -Xlinker -dead_strip \
  -framework Cocoa -framework WebKit -framework Network -framework Security \
  -o "$app/Contents/MacOS/Secret"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Secret</string>
<key>CFBundleIdentifier</key><string>local.harbor.browser</string>
<key>CFBundleName</key><string>eloter</string>
<key>CFBundleDisplayName</key><string>eloter</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.8</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
test -s "$app/Contents/_CodeSignature/CodeResources"
xcrun lipo "$app/Contents/MacOS/Secret" -verify_arch arm64
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/eloter-AppleSilicon.zip"
mkdir "$stage/unpacked"
ditto -x -k "$stage/eloter-AppleSilicon.zip" "$stage/unpacked"
codesign --verify --deep --strict --verbose=2 "$stage/unpacked/eloter.app"
test -s "$stage/unpacked/eloter.app/Contents/_CodeSignature/CodeResources"
test -s "$stage/unpacked/eloter.app/Contents/Resources/AppIcon.icns"
mv "$stage/eloter-AppleSilicon.zip" dist/eloter-AppleSilicon.zip
(cd dist && shasum -a 256 eloter-AppleSilicon.zip > SHA256SUMS)
echo 'Built, signed, and verified the packaged app: dist/eloter-AppleSilicon.zip'
