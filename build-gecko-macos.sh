#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[ "$(uname -s)" = Darwin ] || { echo 'Build the Gecko edition on macOS.' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo 'Use an Apple Silicon Mac runner.' >&2; exit 1; }
mkdir -p build dist
stage=$(mktemp -d "$PWD/build/gecko.XXXXXX")
mounted=false
cleanup() {
  if [ "$mounted" = true ]; then hdiutil detach "$stage/firefox-image" -quiet || true; fi
  rm -rf "$stage"
}
trap cleanup EXIT
app="$stage/eloter.app"
resources="$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$resources/runtime" "$resources/gecko" "$resources/licenses"
firefox_version=160.0
node_version=v26.13.1
curl --fail --location --retry 3 "https://archive.mozilla.org/pub/firefox/releases/$firefox_version/mac/en-US/Firefox%20$firefox_version.dmg" -o "$stage/Firefox.dmg"
curl --fail --location --retry 3 "https://archive.mozilla.org/pub/firefox/releases/$firefox_version/SHA512SUMS" -o "$stage/firefox-sums"
python3 - "$stage/firefox-sums" "$stage/Firefox.dmg" "mac/en-US/Firefox $firefox_version.dmg" <<'PY'
import hashlib,sys
sums={line.split(None,1)[1].strip():line.split(None,1)[0] for line in open(sys.argv[1]) if line.strip()}
assert hashlib.file_digest(open(sys.argv[2],'rb'),'sha512').hexdigest()==sums[sys.argv[3]],'Firefox checksum mismatch'
print('Verified official Firefox download checksum')
PY
mkdir "$stage/firefox-image"
hdiutil attach "$stage/Firefox.dmg" -nobrowse -readonly -mountpoint "$stage/firefox-image" -quiet
mounted=true
codesign --verify --deep --strict --verbose=2 "$stage/firefox-image/Firefox.app"
codesign -d -r- "$stage/firefox-image/Firefox.app" > "$stage/firefox-requirement" 2>&1
python3 - "$stage/firefox-requirement" "$resources/runtime/firefox.json" "$firefox_version" <<'PYMETA'
import json,sys
text=open(sys.argv[1]).read()
requirement=next(line.split('designated => ',1)[1] for line in text.splitlines() if 'designated => ' in line)
assert 'anchor apple' in requirement,'Mozilla signature must be Apple-anchored'
json.dump({'version':sys.argv[3],'requirement':requirement},open(sys.argv[2],'w'))
PYMETA
hdiutil detach "$stage/firefox-image" -quiet
mounted=false
cp "$stage/Firefox.dmg" "$resources/runtime/Firefox.dmg"
curl --fail --location --retry 3 "https://nodejs.org/dist/$node_version/node-$node_version-darwin-arm64.tar.gz" -o "$stage/node.tar.gz"
curl --fail --location --retry 3 "https://nodejs.org/dist/$node_version/SHASUMS256.txt" -o "$stage/node-sums"
python3 - "$stage/node-sums" "$stage/node.tar.gz" "node-$node_version-darwin-arm64.tar.gz" <<'PY'
import hashlib,sys
sums={line.split(None,1)[1].strip():line.split(None,1)[0] for line in open(sys.argv[1]) if line.strip()}
assert hashlib.file_digest(open(sys.argv[2],'rb'),'sha256').hexdigest()==sums[sys.argv[3]],'Node checksum mismatch'
print('Verified official Node.js download checksum')
PY
tar -xzf "$stage/node.tar.gz" -C "$stage"
mkdir -p "$resources/runtime/node/bin"
cp "$stage/node-$node_version-darwin-arm64/bin/node" "$resources/runtime/node/bin/node"
cp "$stage/node-$node_version-darwin-arm64/LICENSE" "$resources/licenses/Node-LICENSE.txt"
codesign --force --sign - --timestamp=none "$resources/runtime/node/bin/node"
cp gecko/package.json gecko/package-lock.json gecko/backend.mjs gecko/home.html "$resources/gecko/"
npm ci --prefix "$resources/gecko" --omit=dev --ignore-scripts
iconset="$stage/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" assets/AppIcon.jpg --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -s format png -z "$retina" "$retina" assets/AppIcon.jpg --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$resources/AppIcon.icns"
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc GeckoLauncher.swift TunnelSettings.swift -O -whole-module-optimization -sdk "$sdk" -target arm64-apple-macos14.0 -framework Cocoa -framework Security -Xlinker -dead_strip -o "$app/Contents/MacOS/Secret"
if otool -L "$app/Contents/MacOS/Secret" | grep -q WebKit; then echo 'Unexpected WebKit dependency' >&2; exit 1; fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Secret</string>
<key>CFBundleIdentifier</key><string>local.harbor.browser</string>
<key>CFBundleName</key><string>eloter</string>
<key>CFBundleDisplayName</key><string>eloter · Gecko edition</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>30</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cat > "$resources/licenses/Firefox-NOTICE.txt" <<'NOTICE'
This package includes an unmodified Mozilla Firefox distribution. Firefox and its trademarks belong to Mozilla. Mozilla's application bundle, signature, and bundled license notices are preserved. Firefox source and licensing: https://www.mozilla.org/MPL/ and https://firefox-source-docs.mozilla.org/. eloter is an independent student project and is not endorsed by Mozilla.
NOTICE
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/eloter-Gecko-AppleSilicon.zip
mkdir "$stage/unpacked"
ditto -x -k dist/eloter-Gecko-AppleSilicon.zip "$stage/unpacked"
codesign --verify --deep --strict --verbose=2 "$stage/unpacked/eloter.app"
(cd dist && shasum -a 256 eloter-Gecko-AppleSilicon.zip > SHA256SUMS)
echo 'Built Gecko/Firefox browser with Node.js backend: dist/eloter-Gecko-AppleSilicon.zip'
