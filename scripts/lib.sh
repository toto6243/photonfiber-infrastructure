#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${PFIF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PFIF_ROOT="$ROOT_DIR"
ENV_FILE="$ROOT_DIR/.env"
TOFU_DIR="$ROOT_DIR/tofu/environments/prod"
ANSIBLE_DIR="$ROOT_DIR/ansible"

info() { printf '\033[1;34m[PFIF]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[PFIF]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[PFIF]\033[0m %s\n' "$*" >&2; exit 1; }

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Missing .env. Run: cp .env.example .env"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  export CLOUDFLARE_API_TOKEN="${PFIF_CLOUDFLARE_API_TOKEN:-}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

truthy() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|yes|y|1) return 0 ;;
    *) return 1 ;;
  esac
}

expand_path() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

resolve_cloudflare_zone_id() {
  if [[ -n "${PFIF_CLOUDFLARE_ZONE_ID:-}" && "${PFIF_CLOUDFLARE_ZONE_ID}" != "AUTO" ]]; then
    export PFIF_CLOUDFLARE_ZONE_ID
    return 0
  fi

  [[ -n "${PFIF_CLOUDFLARE_API_TOKEN:-}" ]] || die "PFIF_CLOUDFLARE_API_TOKEN is required when Cloudflare DNS management is enabled"
  require_cmd curl
  require_cmd jq
  info "Discovering Cloudflare zone ID for ${PFIF_MAIL_DOMAIN}"
  local response zone_id
  response="$(curl -fsS --get \
    -H "Authorization: Bearer ${PFIF_CLOUDFLARE_API_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data-urlencode "name=${PFIF_MAIL_DOMAIN}" \
    --data-urlencode 'status=active' \
    'https://api.cloudflare.com/client/v4/zones')" || die "Cloudflare zone lookup failed"
  zone_id="$(jq -r 'if .success == true and (.result | length) == 1 then .result[0].id else empty end' <<<"$response")"
  [[ -n "$zone_id" ]] || die "Could not uniquely resolve an active Cloudflare zone for ${PFIF_MAIL_DOMAIN}"
  export PFIF_CLOUDFLARE_ZONE_ID="$zone_id"
}

tofu_output_raw() {
  tofu -chdir="$TOFU_DIR" output -raw "$1" 2>/dev/null
}
