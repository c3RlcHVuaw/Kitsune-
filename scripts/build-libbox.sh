#!/bin/sh
# Builds Frameworks/Libbox.xcframework from a pinned sing-box tag.
# shortcut: uses upstream tag set (incl. tailscale/openvpn), trim tags at stage 7 if extension memory is tight.
set -eu
export PATH="$(go env GOPATH)/bin:$PATH"
SING_BOX_TAG=v1.14.4
cd "$(dirname "$0")/.."
SRC=.build/sing-box
[ -d "$SRC" ] || git clone -q --depth 1 --branch "$SING_BOX_TAG" https://github.com/SagerNet/sing-box.git "$SRC"
cd "$SRC"
make lib_install
go run ./cmd/internal/build_libbox -target apple -platform ios,iossimulator,macos
cd - >/dev/null
mkdir -p Frameworks && rm -rf Frameworks/Libbox.xcframework
mv "$SRC/Libbox.xcframework" Frameworks/
echo "Frameworks/Libbox.xcframework ($SING_BOX_TAG)"
