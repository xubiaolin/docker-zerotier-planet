#!/usr/bin/env bash
set -euo pipefail

PLANET_URL=""
FILE_KEY=""
NETWORK_ID=""
ALLOW_INSECURE_HTTP=0

usage() {
  cat <<'USAGE'
Usage:
  install-zerotier-client.sh --planet-url URL --file-key KEY [--network-id NETWORK_ID] [--allow-insecure-http]

Installs ZeroTier One when needed, downloads planet with an Authorization: Bearer header,
replaces the local planet file, restarts ZeroTier, and optionally joins a network.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planet-url)
      [[ $# -ge 2 ]] || fail "--planet-url requires a value"
      PLANET_URL="$2"
      shift 2
      ;;
    --file-key)
      [[ $# -ge 2 ]] || fail "--file-key requires a value"
      FILE_KEY="$2"
      shift 2
      ;;
    --network-id)
      [[ $# -ge 2 ]] || fail "--network-id requires a value"
      NETWORK_ID="$2"
      shift 2
      ;;
    --allow-insecure-http)
      ALLOW_INSECURE_HTTP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail "run this script as root, for example through sudo"
[[ -n "$PLANET_URL" ]] || fail "--planet-url is required"
[[ -n "$FILE_KEY" ]] || fail "--file-key is required"

case "$PLANET_URL" in
  https://*) ;;
  http://*)
    [[ "$ALLOW_INSECURE_HTTP" -eq 1 ]] || fail "plain HTTP planet URLs require --allow-insecure-http"
    ;;
  *)
    fail "--planet-url must start with https://"
    ;;
esac

OS_NAME="$(uname -s)"

find_zerotier_cli() {
  local candidate
  for candidate in \
    "$(command -v zerotier-cli 2>/dev/null || true)" \
    /usr/sbin/zerotier-cli \
    /usr/bin/zerotier-cli \
    /usr/local/bin/zerotier-cli; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_linux() {
  if find_zerotier_cli >/dev/null; then
    return 0
  fi
  need_cmd curl
  curl -fsSL https://install.zerotier.com | bash
}

install_macos() {
  if find_zerotier_cli >/dev/null; then
    return 0
  fi
  need_cmd curl
  need_cmd installer
  local pkg_file
  pkg_file="$(mktemp "${TMPDIR:-/tmp}/zerotier-one.XXXXXX.pkg")"
  curl -fL https://download.zerotier.com/dist/ZeroTier%20One.pkg -o "$pkg_file"
  installer -pkg "$pkg_file" -target /
  rm -f "$pkg_file"
}

restart_linux() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart zerotier-one
  elif command -v service >/dev/null 2>&1; then
    service zerotier-one restart
  else
    fail "neither systemctl nor service is available to restart zerotier-one"
  fi
}

restart_macos() {
  local plist="/Library/LaunchDaemons/com.zerotier.one.plist"
  [[ -f "$plist" ]] || fail "ZeroTier LaunchDaemon not found: $plist"
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
}

case "$OS_NAME" in
  Linux)
    install_linux
    PLANET_PATH="/var/lib/zerotier-one/planet"
    RESTART_COMMAND=restart_linux
    ;;
  Darwin)
    install_macos
    PLANET_PATH="/Library/Application Support/ZeroTier/One/planet"
    RESTART_COMMAND=restart_macos
    ;;
  *)
    fail "unsupported OS: $OS_NAME"
    ;;
esac

need_cmd curl
ZT_CLI="$(find_zerotier_cli)" || fail "zerotier-cli was not found after installation"

tmp_planet="$(mktemp "${TMPDIR:-/tmp}/zerotier-planet.XXXXXX")"
cleanup() {
  rm -f "$tmp_planet"
}
trap cleanup EXIT

curl -fL -H "Authorization: Bearer ${FILE_KEY}" "$PLANET_URL" -o "$tmp_planet"
test -s "$tmp_planet" || fail "downloaded planet file is empty"

install -d -m 0755 "$(dirname "$PLANET_PATH")"
install -m 0644 "$tmp_planet" "$PLANET_PATH"

"$RESTART_COMMAND"
sleep 2

if [[ -n "$NETWORK_ID" ]]; then
  "$ZT_CLI" join "$NETWORK_ID"
fi

printf 'ZeroTier planet installed successfully: %s\n' "$PLANET_PATH"
