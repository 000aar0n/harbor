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
app="$stage/Secrét.app"
mkdir -p "$app/Contents/MacOS"
sdk=$(xcrun --sdk macosx --show-sdk-path)
for arch in arm64 x86_64; do
  xcrun swiftc Harbor.swift Tunnel.swift TunnelSettings.swift MouseCapture.swift -O -sdk "$sdk" -target "${arch}-apple-macos14.0" \
    -framework Cocoa -framework WebKit -framework Network -framework Security \
    -o "$stage/Secret-$arch"
done
xcrun lipo -create "$stage/Secret-arm64" "$stage/Secret-x86_64" \
  -output "$app/Contents/MacOS/Secret"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Secret</string>
<key>CFBundleIdentifier</key><string>local.harbor.browser</string>
<key>CFBundleName</key><string>Secrét</string>
<key>CFBundleDisplayName</key><string>Secrét</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.3</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
test -s "$app/Contents/_CodeSignature/CodeResources"
xcrun lipo "$app/Contents/MacOS/Secret" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/Secret-macOS.zip"
mkdir "$stage/unpacked"
ditto -x -k "$stage/Secret-macOS.zip" "$stage/unpacked"
codesign --verify --deep --strict --verbose=2 "$stage/unpacked/Secrét.app"
test -s "$stage/unpacked/Secrét.app/Contents/_CodeSignature/CodeResources"
mv "$stage/Secret-macOS.zip" dist/Secret-macOS.zip
(cd dist && shasum -a 256 Secret-macOS.zip > SHA256SUMS)
echo 'Built, signed, and verified the packaged app: dist/Secret-macOS.zip'
