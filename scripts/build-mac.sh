#!/bin/sh
# Builds Kitsune for macOS (Release). Unsigned unless TEAM signing is set up in Xcode:
# the VPN extension only runs when signed with a profile that has the Network Extension entitlement.
set -eu
cd "$(dirname "$0")/.."
[ -d Frameworks/Libbox.xcframework/macos-arm64_x86_64 ] || ./scripts/build-libbox.sh
xcodegen generate --quiet
xcodebuild -project Kitsune.xcodeproj -scheme KitsuneMac -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/dd-mac-release CODE_SIGNING_ALLOWED=NO -quiet build
# macOS runs the sing-box core directly (no signed Network Extension needed): bundle the CLI build.
[ -x .build/sing-box-cli ] || { echo "нет .build/sing-box-cli (go build ./cmd/sing-box с тегами из build-libbox.sh)"; exit 1; }
APP=.build/dd-mac-release/Build/Products/Release/Kitsune.app
cp .build/sing-box-cli "$APP/Contents/Resources/sing-box"
# The Go build is static and runs on macOS 14, but was linked with minos 15: lower it so Sonoma accepts it (app target is 14.0).
vtool -set-build-version macos 14.0 14.0 -replace -output "$APP/Contents/Resources/sing-box.tmp" "$APP/Contents/Resources/sing-box" >/dev/null
mv "$APP/Contents/Resources/sing-box.tmp" "$APP/Contents/Resources/sing-box"; chmod +x "$APP/Contents/Resources/sing-box"
codesign --force -s - "$APP/Contents/Resources/sing-box" >/dev/null 2>&1
rm -rf "$APP/Contents/Resources/RuleSets"; cp -R PacketTunnel/RuleSets "$APP/Contents/Resources/RuleSets"
mkdir -p dist && rm -f dist/Kitsune-mac.zip
ditto -c -k --norsrc --noextattr --keepParent .build/dd-mac-release/Build/Products/Release/Kitsune.app dist/Kitsune-mac.zip
echo dist/Kitsune-mac.zip
# Disk image installer: dark window, drag Kitsune onto Applications (dmgbuild, installed on first run).
[ -x .build/venv/bin/dmgbuild ] || { python3 -m venv .build/venv && .build/venv/bin/pip install -q dmgbuild pillow; }
BG=.build/dmg-bg.png
.build/venv/bin/python scripts/make-dmg-bg.py "$BG"
rm -f dist/Kitsune-mac.dmg
KITSUNE_APP="$PWD/.build/dd-mac-release/Build/Products/Release/Kitsune.app" KITSUNE_BG="$PWD/$BG" \
  .build/venv/bin/dmgbuild -s scripts/dmg-settings.py Kitsune dist/Kitsune-mac.dmg >/dev/null
echo dist/Kitsune-mac.dmg
