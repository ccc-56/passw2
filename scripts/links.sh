#!/usr/bin/env bash
# Prints client share links (VLESS-REALITY + Hysteria2) for every device and
# writes local client files under clients/<device>/.
# Safe to run any time; reads everything from Terraform state.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws openssl basenc jq

tf_init

IP="$(tf_out public_ip)"
PORT="$(tf_out proxy_port)"
HY_PORT="$(tf_out hysteria_port)"
SNI="$(tf_out reality_server_name)"
SID="$(tf_out reality_short_id)"
PBK="$(x25519_public "$(tf_out reality_private_key)")"
PIN="$(hysteria_pin)"
TAG="${LINK_TAG:-passw2-seoul}"

OUT="$REPO_ROOT/clients"
mkdir -p "$OUT"
: >"$OUT/share-links.txt"
chmod 600 "$OUT/share-links.txt"

# Percent-encode the few URI-hostile characters that can appear in a Hysteria2
# password or a device name (both are limited to [A-Za-z0-9-] here, but stay safe).
urlencode() {
  jq -rn --arg s "$1" '$s | @uri'
}

echo
echo "node        : $IP  (vless ${PORT}/tcp, hysteria2 ${HY_PORT}/udp, sni=$SNI)"

while IFS= read -r user; do
  UUID="$(tf_out_key users "$user")"
  HY_PASS="$(tf_out_key hysteria_passwords "$user")"

  VLESS="vless://$UUID@$IP:$PORT?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PBK&sid=$SID&type=tcp&flow=xtls-rprx-vision#$TAG-$user"
  # insecure=1 is required because the certificate is self-signed; pinSHA256
  # is what actually authenticates the server for clients that support it.
  HY2="hysteria2://$(urlencode "$user"):$(urlencode "$HY_PASS")@$IP:$HY_PORT/?sni=$SNI&insecure=1&pinSHA256=$PIN#$TAG-$user-hy2"

  dir="$OUT/$user"
  mkdir -p "$dir"
  printf '%s\n%s\n' "$VLESS" "$HY2" >"$dir/share-links.txt"
  printf '%s\n%s\n' "$VLESS" "$HY2" >>"$OUT/share-links.txt"

  # sing-box / Clash.Meta users can import the share links directly; this JSON is
  # for xray-core clients and for scripts/verify.sh.
  cat >"$dir/xray-client.json" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "socks",
      "listen": "127.0.0.1",
      "port": ${SOCKS_PORT:-10808},
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$IP",
            "port": $PORT,
            "users": [
              { "id": "$UUID", "encryption": "none", "flow": "xtls-rprx-vision" }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "$SNI",
          "fingerprint": "chrome",
          "publicKey": "$PBK",
          "shortId": "$SID"
        }
      }
    }
  ]
}
JSON

  # Official hysteria client config, also used by scripts/verify.sh.
  cat >"$dir/hysteria-client.yaml" <<YAML
server: $IP:$HY_PORT
auth: $user:$HY_PASS
tls:
  sni: $SNI
  insecure: true
  pinSHA256: "$PIN"
socks5:
  listen: 127.0.0.1:${HY_SOCKS_PORT:-10809}
http:
  listen: 127.0.0.1:${HY_HTTP_PORT:-10810}
YAML
  chmod 600 "$dir"/*

  echo
  echo "[$user]"
  echo "  vless     : $VLESS"
  echo "  hysteria2 : $HY2"
done < <(tf_users)

echo
echo "wrote clients/share-links.txt and clients/<device>/{share-links.txt,xray-client.json,hysteria-client.yaml} (git-ignored)"
if command -v qrencode >/dev/null && [ -n "${QR:-}" ]; then
  while IFS= read -r link; do
    echo
    echo "$link"
    qrencode -t ANSIUTF8 "$link"
  done <"$OUT/share-links.txt"
else
  echo "set QR=1 to also print QR codes (needs qrencode)"
fi
