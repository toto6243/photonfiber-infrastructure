#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env
require_cmd tofu

export CLOUDFLARE_API_TOKEN="${PFIF_CLOUDFLARE_API_TOKEN:-}"
cmd="${1:-}"
shift || true

case "$cmd" in
  init)
    tofu -chdir="$TOFU_DIR" init -reconfigure -backend-config=backend.hcl "$@"
    ;;
  plan)
    tofu -chdir="$TOFU_DIR" plan "$@"
    ;;
  apply)
    tofu -chdir="$TOFU_DIR" apply "$@"
    ;;
  destroy)
    tofu -chdir="$TOFU_DIR" destroy "$@"
    ;;
  output)
    tofu -chdir="$TOFU_DIR" output "$@"
    ;;
  validate)
    tofu -chdir="$TOFU_DIR" validate "$@"
    ;;
  *)
    tofu -chdir="$TOFU_DIR" "$cmd" "$@"
    ;;
esac
