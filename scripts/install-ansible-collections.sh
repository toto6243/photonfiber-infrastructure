#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_cmd ansible-galaxy
info "Installing required Ansible collections"
ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml"
