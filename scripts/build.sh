#!/usr/bin/env bash
# Builds dist/NAVTOK.exe (static, no cgo, GUI subsystem) and dist/NavtokDiscord-<version>.zip.
#   ./scripts/build.sh v1.0.0
# Private guild build with a baked-in webhook (members get zero questions):
#   NAVTOK_DEFAULT_WEBHOOK=https://discord.com/api/webhooks/... ./scripts/build.sh v1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${NAVTOK_OUT:-dist}"
mkdir -p "$OUT"
PKG=github.com/navtok/navtok-discord/companion/internal/config
LDFLAGS="-H windowsgui -s -w -X main.version=${VERSION}"
if [[ -n "${NAVTOK_DEFAULT_WEBHOOK:-}" ]]; then
  LDFLAGS="$LDFLAGS -X ${PKG}.DefaultWebhook=${NAVTOK_DEFAULT_WEBHOOK}"
fi
if [[ -n "${NAVTOK_UPDATE_REPO:-}" ]]; then
  LDFLAGS="$LDFLAGS -X ${PKG}.UpdateRepo=${NAVTOK_UPDATE_REPO}"
fi
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$LDFLAGS" -o "$OUT/NAVTOK.exe" ./companion/cmd/navtok

# addon zip (for people who want to install the addon by hand; NAVTOK.exe installs it itself)
if [[ -z "${NAVTOK_DEFAULT_WEBHOOK:-}" ]]; then
  (cd addon && rm -f "../$OUT/NavtokDiscord-${VERSION}.zip" && zip -qr "../$OUT/NavtokDiscord-${VERSION}.zip" NavtokDiscord)
  (cd "$OUT" && sha256sum NAVTOK.exe "NavtokDiscord-${VERSION}.zip" > SHA256SUMS.txt)
fi
ls -la "$OUT"
