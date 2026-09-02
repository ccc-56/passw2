#!/usr/bin/env bash
# Swaps in a fresh static IPv4 without touching the instance or the keys.
# Use this when the current address gets blackholed by the GFW: the client link
# is reprinted with the new IP, everything else stays the same.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws openssl basenc jq

tf_init
terraform -chdir="$TF_DIR" apply -input=false -auto-approve \
  -replace=aws_lightsail_static_ip.node \
  -replace=aws_lightsail_static_ip_attachment.node

"$REPO_ROOT/scripts/links.sh"
