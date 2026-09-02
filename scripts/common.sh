#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts, not meant to be run directly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
REGION="${AWS_REGION:-ap-northeast-2}"

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null || {
      echo "missing required command: $bin" >&2
      exit 1
    }
  done
}

account_id() {
  aws sts get-caller-identity --query Account --output text
}

state_bucket() {
  echo "${TF_STATE_BUCKET:-passw2-tfstate-$(account_id)}"
}

# The state bucket outlives `down.sh` so a later `up.sh` — even from a brand new
# machine — reuses the same keys, UUID and therefore the same client links.
ensure_state_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    return
  fi
  echo "creating state bucket s3://$bucket"
  aws s3api create-bucket \
    --bucket "$bucket" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  aws s3api put-bucket-versioning --bucket "$bucket" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$bucket" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$bucket" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
}

tf_init() {
  local bucket
  bucket="$(state_bucket)"
  ensure_state_bucket "$bucket"
  terraform -chdir="$TF_DIR" init -reconfigure -input=false \
    -backend-config="bucket=$bucket" -backend-config="region=$REGION" >/dev/null
}

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

# For map outputs (users, hysteria_passwords): prints the value for one key.
tf_out_key() {
  terraform -chdir="$TF_DIR" output -json "$1" | jq -r --arg k "$2" '.[$k]'
}

# Device names, one per line.
tf_users() {
  terraform -chdir="$TF_DIR" output -json users | jq -r 'keys[]'
}

# Hysteria2 clients pin the self-signed certificate by its SHA-256 fingerprint
# (colon-separated hex, as `openssl x509 -fingerprint` prints it).
hysteria_pin() {
  tf_out hysteria_cert_pem | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2
}

# Derives the REALITY public key from the private key (raw 32-byte X25519 scalar
# in base64url). Xray only ever sees the private half; clients need the public one.
x25519_public() {
  local priv_b64u="$1" priv_b64 der pub
  # base64url -> base64, and restore the padding GNU base64 insists on.
  priv_b64="$(printf '%s' "$priv_b64u" | tr '_-' '/+')"
  while [ $((${#priv_b64} % 4)) -ne 0 ]; do priv_b64+="="; done
  der="$(mktemp)"
  pub="$(mktemp)"
  {
    # DER prefix for a PKCS#8 X25519 private key, followed by the raw 32-byte scalar.
    printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'
    printf '%s' "$priv_b64" | base64 -d
  } >"$der"
  openssl pkey -inform DER -in "$der" -pubout -outform DER | tail -c 32 >"$pub"
  basenc --base64url <"$pub" | tr -d '='
  rm -f "$der" "$pub"
}
