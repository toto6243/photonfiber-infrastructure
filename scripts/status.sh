#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

info "Infrastructure outputs"
tofu -chdir="$TOFU_DIR" output || die "No OpenTofu state. Deploy first."

public_ip="$(tofu_output_raw public_ip_address)"
admin_user="$(tofu_output_raw admin_username)"
private_key="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"

printf '\n'
info "Remote Mailcow status"
ssh -i "$private_key" -o StrictHostKeyChecking=accept-new "$admin_user@$public_ip" \
  'cd /opt/mailcow-dockerized && sudo docker compose ps'
