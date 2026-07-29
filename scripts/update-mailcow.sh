#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env
"$ROOT_DIR/scripts/generate-inventory.sh"
"$ROOT_DIR/scripts/ansible.sh" update-mailcow.yml
