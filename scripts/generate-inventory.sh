#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env
require_cmd tofu

public_ip="$(tofu_output_raw public_ip_address)" || die "OpenTofu outputs are unavailable. Run ./pfif apply first."
admin_user="$(tofu_output_raw admin_username)"
backup_enabled="$(tofu_output_raw backup_storage_enabled)"
storage_account="$(tofu_output_raw backup_storage_account_name || true)"
storage_container="$(tofu_output_raw backup_container_name || true)"
private_key="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"

python3 - "$ANSIBLE_DIR/inventory/hosts.yml" "$public_ip" "$admin_user" "$private_key" "$backup_enabled" "$storage_account" "$storage_container" <<'PY'
from pathlib import Path
import json, sys
path, ip, user, key, enabled, account, container = sys.argv[1:]
text = f"""---
all:
  children:
    mailcow:
      hosts:
        mailcow01:
          ansible_host: {json.dumps(ip)}
          ansible_user: {json.dumps(user)}
          ansible_ssh_private_key_file: {json.dumps(key)}
          azure_backup_enabled: {enabled.lower()}
          azure_storage_account: {json.dumps(account)}
          azure_storage_container: {json.dumps(container)}
"""
Path(path).write_text(text)
Path(path).chmod(0o600)
PY

info "Generated Ansible inventory for $admin_user@$public_ip"
