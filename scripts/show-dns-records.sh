#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

if tofu -chdir="$TOFU_DIR" output -json dns_records >/dev/null 2>&1; then
  tofu -chdir="$TOFU_DIR" output -json dns_records | jq -r '
    to_entries[] |
    .value as $r |
    "\($r.type)\t\($r.name)\t\($r.value)" +
    (if $r.priority then "\tpriority=\($r.priority)" else "" end) +
    (if $r.proxy then "\t\($r.proxy)" else "" end)
  '
else
  warn "Infrastructure outputs are unavailable; run ./pfif apply first"
fi

cat <<EOF

DKIM is generated only after you add ${PFIF_MAIL_DOMAIN} in the Mailcow UI.
Open: https://${PFIF_MAIL_HOSTNAME}
Then: Configuration -> ARC/DKIM keys -> copy the TXT record into Cloudflare.
All mail-related Cloudflare records must remain DNS-only, not proxied.
EOF
