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
app="$stage/Harbor.app"
mkdir -p "$app/Contents/MacOS"
sdk=$(xcrun --sdk macosx --show-sdk-path)
for arch in arm64 x86_64; do
  xcrun swiftc Harbor.swift -O -sdk "$sdk" -target "${arch}-apple-macos14.0" \
    -framework Cocoa -framework WebKit -framework Network \
    -o "$stage/Harbor-$arch"
done
xcrun lipo -create "$stage/Harbor-arm64" "$stage/Harbor-x86_64" \
  -output "$app/Contents/MacOS/Harbor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Harbor</string>
<key>CFBundleIdentifier</key><string>local.harbor.browser</string>
<key>CFBundleName</key><string>Harbor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
test -s "$app/Contents/_CodeSignature/CodeResources"
xcrun lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/Harbor"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/Harbor-macOS.zip"
mkdir "$stage/unpacked"
ditto -x -k "$stage/Harbor-macOS.zip" "$stage/unpacked"
codesign --verify --deep --strict --verbose=2 "$stage/unpacked/Harbor.app"
test -s "$stage/unpacked/Harbor.app/Contents/_CodeSignature/CodeResources"
mv "$stage/Harbor-macOS.zip" dist/Harbor-macOS.zip
(cd dist && shasum -a 256 Harbor-macOS.zip > SHA256SUMS)
echo 'Built, signed, and verified the packaged app: dist/Harbor-macOS.zip'
