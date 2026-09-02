#!/usr/bin/env bash
# End-to-end check: runs throwaway xray and hysteria clients against the node
# and confirms traffic actually exits through it (curl's observed IP == node IP)
# over both VLESS-REALITY (tcp) and Hysteria2 (udp).
#
#   DEVICE=laptop ./scripts/verify.sh   # which device's credentials to use (default: first)
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws curl unzip openssl basenc jq

SOCKS_PORT="${SOCKS_PORT:-10808}"
HY_SOCKS_PORT="${HY_SOCKS_PORT:-10809}"
export SOCKS_PORT HY_SOCKS_PORT
"$REPO_ROOT/scripts/links.sh" >/dev/null

DEVICE="${DEVICE:-$(tf_users | head -1)}"
CLIENT_DIR="$REPO_ROOT/clients/$DEVICE"
[ -d "$CLIENT_DIR" ] || {
  echo "unknown device '$DEVICE'; known: $(tf_users | paste -sd,)" >&2
  exit 1
}

BIN_DIR="$REPO_ROOT/.local"
mkdir -p "$BIN_DIR"

# Resolves the redirect of /releases/latest instead of calling the GitHub API,
# which rate-limits unauthenticated clients to 60 requests/hour.
latest_tag() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")"
  printf '%s\n' "${url#*/releases/tag/}"
}

XRAY="$BIN_DIR/xray"
if [ ! -x "$XRAY" ]; then
  version="${XRAY_VERSION:-$(latest_tag XTLS/Xray-core)}"
  echo "downloading xray-core $version"
  curl -fsSL -o "$BIN_DIR/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/$version/Xray-linux-64.zip"
  unzip -o -q "$BIN_DIR/xray.zip" -d "$BIN_DIR" xray
  chmod +x "$XRAY"
fi

HYSTERIA="$BIN_DIR/hysteria"
if [ ! -x "$HYSTERIA" ]; then
  # Hysteria tags look like app/v2.12.2; the slash is %2F in download URLs.
  version="${HYSTERIA_VERSION:-$(latest_tag HyNetworks/hysteria)}"
  echo "downloading hysteria $version"
  curl -fsSL -o "$HYSTERIA" \
    "https://github.com/HyNetworks/hysteria/releases/download/${version//\//%2F}/hysteria-linux-amd64"
  chmod +x "$HYSTERIA"
fi

"$XRAY" run -c "$CLIENT_DIR/xray-client.json" >"$BIN_DIR/xray-client.log" 2>&1 &
xray_pid=$!
"$HYSTERIA" client -c "$CLIENT_DIR/hysteria-client.yaml" >"$BIN_DIR/hysteria-client.log" 2>&1 &
hy_pid=$!
trap 'kill $xray_pid $hy_pid 2>/dev/null || true' EXIT
sleep 3

node_ip="$(tf_out public_ip)"
echo "device : $DEVICE"
echo "node ip: $node_ip"

check_exit() {
  local label="$1" port="$2" log="$3" seen_ip
  seen_ip="$(curl -fsS --max-time 25 --socks5-hostname "127.0.0.1:$port" https://api.ipify.org || true)"
  echo "$label exit ip: ${seen_ip:-<none>}"
  [ "$node_ip" = "$seen_ip" ] || {
    echo "FAIL: $label traffic is not exiting through the node" >&2
    tail -20 "$log" >&2
    return 1
  }
  for url in https://www.google.com/generate_204 https://www.youtube.com https://x.com; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 \
      --socks5-hostname "127.0.0.1:$port" "$url")"
    echo "  $url -> HTTP $code"
  done
}

status=0
check_exit "vless-reality" "$SOCKS_PORT" "$BIN_DIR/xray-client.log" || status=1
check_exit "hysteria2" "$HY_SOCKS_PORT" "$BIN_DIR/hysteria-client.log" || status=1

[ "$status" -eq 0 ] && echo "OK: both inbounds work"
exit "$status"
