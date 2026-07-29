#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

public_ip="$(tofu_output_raw public_ip_address)"
admin_user="$(tofu_output_raw admin_username)"
private_key="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"

info "Waiting for SSH on $public_ip"
for attempt in $(seq 1 90); do
  if ssh -i "$private_key" \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=accept-new \
      "$admin_user@$public_ip" true 2>/dev/null; then
    info "SSH is ready"
    exit 0
  fi
  sleep 10
done
die "SSH did not become ready within 15 minutes"
