#!/bin/sh
# Refreshes the Russian rule-set snapshot bundled into the PacketTunnel extension.
# sing-box uses it only until its first successful download (see initial_path in ConfigBuilder).
set -eu
cd "$(dirname "$0")/.."
BASE=https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box
DIR=PacketTunnel/RuleSets
mkdir -p "$DIR"
for item in rule-set-geosite/geosite-category-ru rule-set-geosite/geosite-category-gov-ru \
            rule-set-geosite/geosite-ru-available-only-inside rule-set-geoip/geoip-ru; do
  tag=$(basename "$item")
  curl -fsSL --retry 3 -o "$DIR/$tag.srs.tmp" "$BASE/$item.srs"
  # A truncated or HTML error page must not replace a good snapshot.
  [ "$(wc -c < "$DIR/$tag.srs.tmp")" -gt 500 ] || { echo "too small: $tag" >&2; rm "$DIR/$tag.srs.tmp"; exit 1; }
  mv "$DIR/$tag.srs.tmp" "$DIR/$tag.srs"
done
date -u +%Y-%m-%d > "$DIR/SNAPSHOT_DATE"
ls -l "$DIR"
