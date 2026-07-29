#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

warn "This destroys the PFIF Mailcow VM, data disk, public IP, network and backup storage."
read -r -p "Type DESTROY to continue: " confirmation
[[ "$confirmation" == "DESTROY" ]] || die "Destroy cancelled"
"$ROOT_DIR/scripts/configure.sh"
"$ROOT_DIR/scripts/bootstrap-state.sh"
"$ROOT_DIR/scripts/tofu.sh" init
"$ROOT_DIR/scripts/tofu.sh" destroy
