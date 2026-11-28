#!/usr/bin/env bash
# Builds dist/NAVTOK.exe (static, no cgo, GUI subsystem), dist/navtok-linux-amd64 (static) and
# dist/NavtokDiscord-<version>.zip.
#   ./scripts/build.sh v1.0.0
# Private guild build with a baked-in webhook (members get zero questions):
#   NAVTOK_DEFAULT_WEBHOOK=https://discord.com/api/webhooks/... ./scripts/build.sh v1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${NAVTOK_OUT:-dist}"
mkdir -p "$OUT"
PKG=github.com/vebbbbb/addon-discord/companion/internal/config
LDFLAGS="-H windowsgui -s -w -X main.version=${VERSION}"
if [[ -n "${NAVTOK_DEFAULT_WEBHOOK:-}" ]]; then
  LDFLAGS="$LDFLAGS -X ${PKG}.DefaultWebhook=${NAVTOK_DEFAULT_WEBHOOK}"
fi
if [[ -n "${NAVTOK_UPDATE_REPO:-}" ]]; then
  LDFLAGS="$LDFLAGS -X ${PKG}.UpdateRepo=${NAVTOK_UPDATE_REPO}"
fi
# stamp the release version into the addon that gets embedded (shown by /navtok), restore after
if [[ "$VERSION" == v* ]]; then
  cp addon/NavtokDiscord/Core.lua /tmp/navtok-core.lua.bak
  cp addon/NavtokDiscord/NavtokDiscord.toc /tmp/navtok-toc.bak
  trap 'cp /tmp/navtok-core.lua.bak addon/NavtokDiscord/Core.lua; cp /tmp/navtok-toc.bak addon/NavtokDiscord/NavtokDiscord.toc' EXIT
  sed -i "s/^ns.VERSION = .*/ns.VERSION = \"${VERSION#v}\"/" addon/NavtokDiscord/Core.lua
  sed -i "s/^## Version: .*/## Version: ${VERSION#v}/" addon/NavtokDiscord/NavtokDiscord.toc
fi
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$LDFLAGS" -o "$OUT/NAVTOK.exe" ./companion/cmd/navtok
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "${LDFLAGS#-H windowsgui }" -o "$OUT/navtok-linux-amd64" ./companion/cmd/navtok

# addon zip (for people who want to install the addon by hand; NAVTOK.exe installs it itself)
if [[ -z "${NAVTOK_DEFAULT_WEBHOOK:-}" ]]; then
  (cd addon && rm -f "../$OUT/NavtokDiscord-${VERSION}.zip" && zip -qr "../$OUT/NavtokDiscord-${VERSION}.zip" NavtokDiscord)
  (cd "$OUT" && sha256sum NAVTOK.exe navtok-linux-amd64 "NavtokDiscord-${VERSION}.zip" > SHA256SUMS.txt)
fi
ls -la "$OUT"
