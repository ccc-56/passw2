#!/usr/bin/env bash
# Destroys everything that costs money so the bill goes to zero.
#
# Only the AWS resources are targeted: the random_*/tls_* resources holding the
# per-device UUIDs and Hysteria2 passwords, the REALITY keypair and the Hysteria2
# certificate stay in state, so a later `up.sh` rebuilds the node with the *same*
# credentials and the client links you already imported keep working (only the
# IP changes).
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require terraform aws

BILLED_RESOURCES=(
  aws_lightsail_instance_public_ports.node
  aws_lightsail_static_ip_attachment.node
  aws_lightsail_instance.node
  aws_lightsail_static_ip.node
  aws_lightsail_key_pair.node
)

tf_init
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve \
  "${BILLED_RESOURCES[@]/#/-target=}" "$@"

find "$REPO_ROOT/clients" -type f ! -name 'node-key.pem' -delete 2>/dev/null || true
echo "node destroyed; UUIDs, passwords and keys kept in s3://$(state_bucket)"
