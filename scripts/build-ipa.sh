#!/bin/sh
# Builds an unsigned Kitsune.ipa for re-signing in ESign (or any other re-signer).
set -eu
cd "$(dirname "$0")/.."
[ -d Frameworks/Libbox.xcframework ] || ./scripts/build-libbox.sh
xcodegen generate --quiet
xcodebuild -project Kitsune.xcodeproj -scheme Kitsune -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/dd-device \
  CODE_SIGNING_ALLOWED=NO -quiet build
rm -rf .build/ipa && mkdir -p .build/ipa/Payload
cp -R .build/dd-device/Build/Products/Release-iphoneos/Kitsune.app .build/ipa/Payload/
mkdir -p dist
(cd .build/ipa && zip -qry ../../dist/Kitsune.ipa Payload)
echo "dist/Kitsune.ipa"
