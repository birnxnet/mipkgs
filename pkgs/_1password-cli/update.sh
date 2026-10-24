#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq nurl xq-xml

set -euo pipefail

cd -- "$(dirname "$(readlink -f "$0")")"

# The beta channel takes the newest release of any kind, so a stable release
# newer than the last beta is picked up too.
case "${UPDATE_NIX_ATTR_PATH:-${1:-_1password-cli}}" in
  _1password-cli | stable)
    channel="stable"
    selector='article:not(.beta) h3'
    ;;
  _1password-cli-beta | beta)
    channel="beta"
    selector='article h3'
    ;;
  *)
    echo "Unknown attribute path or channel ${UPDATE_NIX_ATTR_PATH:-${1}}" >&2
    exit 1
    ;;
esac

fetch_linux() {
  VER="$1"
  ARCH="$2"
  URL="https://cache.agilebits.com/dist/1P/op2/pkg/v${VER}/op_${ARCH}_v${VER}.zip"
  nurl --hash --expr "(import <nixpkgs> { }).fetchzip { url = \"$URL\"; stripRoot = false; }"
}

fetch_darwin() {
  VER="$1"
  URL="https://cache.agilebits.com/dist/1P/op2/pkg/v${VER}/op_apple_universal_v${VER}.pkg"
  nurl --hash --expr "(import <nixpkgs> { }).fetchurl { url = \"$URL\"; }"
}

CLI_VERSION="$(curl -Ls https://app-updates.agilebits.com/product_history/CLI2 | xq -q "$selector" | awk 'NF && !v { v = $1 } END { print v }')"
if [ -z "$CLI_VERSION" ]; then
  echo "ERROR: failed to determine latest CLI ${channel} version"
  exit 1
fi

jq \
  --arg channel "$channel" \
  --arg version "$CLI_VERSION" \
  --arg linux_arm64 "$(fetch_linux "$CLI_VERSION" "linux_arm64")" \
  --arg linux_386 "$(fetch_linux "$CLI_VERSION" "linux_386")" \
  --arg linux_amd64 "$(fetch_linux "$CLI_VERSION" "linux_amd64")" \
  --arg apple_universal "$(fetch_darwin "$CLI_VERSION")" \
  '.[$channel] = {
    version: $version,
    hashes: {
      linux_arm64: $linux_arm64,
      linux_386: $linux_386,
      linux_amd64: $linux_amd64,
      apple_universal: $apple_universal
    }
  }' sources.json > sources.json.tmp
mv sources.json.tmp sources.json
