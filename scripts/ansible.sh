#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env
require_cmd ansible-playbook
"$ROOT_DIR/scripts/install-ansible-collections.sh"

playbook="${1:-site.yml}"
shift || true
[[ -f "$ANSIBLE_DIR/inventory/hosts.yml" ]] || "$ROOT_DIR/scripts/generate-inventory.sh"

cd "$ANSIBLE_DIR"
ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" ansible-playbook \
  -i inventory/hosts.yml \
  "playbooks/$playbook" \
  "$@"
