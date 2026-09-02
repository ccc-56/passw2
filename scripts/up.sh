#!/usr/bin/env bash
# Creates (or updates) the Seoul node and prints client links. Idempotent.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws openssl basenc jq

tf_init
terraform -chdir="$TF_DIR" apply -input=false -auto-approve "$@"

IP="$(tf_out public_ip)"
PORT="$(tf_out proxy_port)"

# Both services are (re)started together at the end of user-data, so an open
# TCP port means Hysteria2 is up too; verify.sh checks both properly.
echo "waiting for xray on $IP:$PORT (cloud-init needs ~2-3 minutes)"
for _ in $(seq 1 60); do
  if timeout 5 bash -c "cat </dev/null >/dev/tcp/$IP/$PORT" 2>/dev/null; then
    echo "port $PORT is open"
    break
  fi
  sleep 10
done

"$REPO_ROOT/scripts/links.sh"
