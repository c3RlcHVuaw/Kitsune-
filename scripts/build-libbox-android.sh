#!/bin/bash
# Собирает libbox.aar (sing-box для Android) в android/app/libs. Нужны Go, JDK 17, Android SDK+NDK.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=.build/sing-box
[ -d "$SRC" ] || git clone --depth 1 --branch v1.14.4 https://github.com/SagerNet/sing-box "$SRC"
cd "$SRC"
export GOTOOLCHAIN=go1.26.10   # Go 1.27 не собирает (os.checkPidfdOnce)
go install -v github.com/sagernet/gomobile/cmd/gomobile@latest github.com/sagernet/gomobile/cmd/gobind@latest
gomobile init
# -checklinkname=0 обязателен, иначе падает линковка
gomobile bind -v -o ../../android/app/libs/libbox.aar -target android/arm64 -androidapi 23 \
  -javapkg=io.nekohasekai -libname=box \
  -tags "with_gvisor,with_quic,with_utls,with_clash_api,with_conntrack" \
  -ldflags "-checklinkname=0 -s -w -buildid=" ./experimental/libbox
