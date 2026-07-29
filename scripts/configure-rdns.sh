#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

best_effort=false
[[ "${1:-}" == "--best-effort" ]] && best_effort=true

if ! truthy "${PFIF_CONFIGURE_REVERSE_DNS:-true}"; then
  info "Reverse DNS is disabled in .env"
  exit 0
fi

public_ip="$(tofu_output_raw public_ip_address 2>/dev/null || true)"
resource_group="$(tofu_output_raw resource_group_name 2>/dev/null || true)"
public_ip_name="$(tofu_output_raw public_ip_name 2>/dev/null || true)"
hostname="${PFIF_MAIL_HOSTNAME}"

if [[ -z "$public_ip" || -z "$resource_group" || -z "$public_ip_name" ]]; then
  $best_effort && { warn "Skipping rDNS because infrastructure outputs are unavailable"; exit 0; }
  die "Infrastructure outputs are unavailable"
fi

resolve_mail_host() {
  python3 - "$hostname" <<'PY' 2>/dev/null || true
import socket, sys
try:
    print('\n'.join(sorted({x[4][0] for x in socket.getaddrinfo(sys.argv[1], 25, socket.AF_INET)})))
except OSError:
    pass
PY
}

answers="$(resolve_mail_host)"
resolved=false
if grep -Fxq "$public_ip" <<<"$answers"; then
  resolved=true
elif $best_effort; then
  warn "Forward DNS is not ready; run ./pfif rdns after $hostname resolves to $public_ip"
  exit 0
else
  info "Waiting for $hostname to resolve to $public_ip before setting PTR"
  for _ in $(seq 1 60); do
    sleep 10
    answers="$(resolve_mail_host)"
    if grep -Fxq "$public_ip" <<<"$answers"; then
      resolved=true
      break
    fi
  done
fi

if ! $resolved; then
  $best_effort && { warn "Forward DNS is not ready; run ./pfif rdns later"; exit 0; }
  die "$hostname does not resolve to $public_ip yet"
fi

az network public-ip update \
  --resource-group "$resource_group" \
  --name "$public_ip_name" \
  --reverse-fqdn "$hostname" \
  --output none
info "PTR/rDNS configured: $public_ip -> $hostname"
