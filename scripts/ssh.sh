#!/usr/bin/env bash
# SSH into the node using the key Terraform generated. Extra args are passed to ssh.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws ssh

tf_init

KEY="$REPO_ROOT/clients/node-key.pem"
mkdir -p "$(dirname "$KEY")"
tf_out ssh_private_key >"$KEY"
chmod 600 "$KEY"

exec ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$(tf_out public_ip)" "$@"
