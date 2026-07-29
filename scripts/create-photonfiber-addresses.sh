#!/usr/bin/env bash
set -euo pipefail

log() { printf '\n[PFIF Addresses] %s\n' "$*"; }
die() { printf '\n[PFIF Addresses] ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

need az
need curl
need jq

MAIL_DOMAIN="${MAIL_DOMAIN:-photonfiber.pk}"
MAILCOW_API_URL="${MAILCOW_API_URL:-https://mail.${MAIL_DOMAIN}}"
TARGET_MAILBOX="${TARGET_MAILBOX:-admin@${MAIL_DOMAIN}}"
ACS_RESOURCE_GROUP="${ACS_RESOURCE_GROUP:-pfif-email-rg}"
ACS_EMAIL_SERVICE="${ACS_EMAIL_SERVICE:-photonfiber-email-service}"

ADDRESSES=(
  "info|Photon Fiber Information|1"
  "support|Photon Fiber Support|1"
  "billing|Photon Fiber Billing|1"
  "noreply|Photon Fiber Notifications|1"
  "dmarc|Photon Fiber DMARC Reports|0"
)

if [[ -z "${MAILCOW_API_KEY:-}" ]]; then
  printf 'Enter the Mailcow read/write API key: ' >&2
  IFS= read -r -s MAILCOW_API_KEY
  printf '\n' >&2
fi
[[ -n "$MAILCOW_API_KEY" ]] || die "Mailcow API key is empty"

MAILCOW_API_URL="${MAILCOW_API_URL%/}"

mailcow_api() {
  local method="$1" endpoint="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" "${MAILCOW_API_URL}${endpoint}" \
      -H "X-API-Key: ${MAILCOW_API_KEY}" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -fsS -X "$method" "${MAILCOW_API_URL}${endpoint}" \
      -H "X-API-Key: ${MAILCOW_API_KEY}" \
      -H "Content-Type: application/json"
  fi
}

log "Checking Azure CLI login"
az account show >/dev/null 2>&1 || die "Azure CLI is not logged in. Run: az login"

log "Checking Mailcow API access"
domains_json="$(mailcow_api GET "/api/v1/get/domain/all")" || die "Could not access the Mailcow API"

if ! jq -e --arg domain "$MAIL_DOMAIN" '
  if type == "array" then
    any(.[]; (.domain // .domain_name // .) == $domain)
  elif type == "object" then
    has($domain)
    or (.domain // .domain_name // "") == $domain
    or any(.[]?; (.domain // .domain_name // .) == $domain)
  else
    false
  end
' >/dev/null <<<"$domains_json"; then
  printf "%s\n" "$domains_json" | jq 'if type=="object" then keys else . end' >&2
  die "Domain ${MAIL_DOMAIN} was not found through the Mailcow API"
fi

log "Reading existing Mailcow aliases"
aliases_json="$(mailcow_api GET "/api/v1/get/alias/all")" || die "Could not read Mailcow aliases"

created_aliases=0
skipped_aliases=0
created_senders=0
updated_senders=0

for item in "${ADDRESSES[@]}"; do
  IFS='|' read -r local_part display_name sogo_visible <<<"$item"
  address="${local_part}@${MAIL_DOMAIN}"

  if jq -e --arg address "$address" '
    if type == "array" then any(.[]; (.address // "") == $address) else false end
  ' >/dev/null <<<"$aliases_json"; then
    log "Mailcow alias already exists: ${address}"
    skipped_aliases=$((skipped_aliases + 1))
  else
    payload="$(
      jq -nc \
        --arg address "$address" \
        --arg goto "$TARGET_MAILBOX" \
        --arg active "1" \
        --arg sogo_visible "$sogo_visible" \
        '{active:$active,address:$address,goto:$goto,sogo_visible:$sogo_visible}'
    )"

    response="$(mailcow_api POST "/api/v1/add/alias" "$payload")" || die "Failed to create Mailcow alias ${address}"

    if jq -e '
      if type == "array" then
        all(.[]; ((.type // "") | ascii_downcase) != "danger" and ((.type // "") | ascii_downcase) != "error")
      elif type == "object" then
        ((.type // "") | ascii_downcase) != "danger" and ((.type // "") | ascii_downcase) != "error"
      else true end
    ' >/dev/null <<<"$response"; then
      log "Created Mailcow alias: ${address} -> ${TARGET_MAILBOX}"
      created_aliases=$((created_aliases + 1))
    else
      jq . <<<"$response" >&2
      die "Mailcow reported an error while creating ${address}"
    fi
  fi

  if az communication email domain sender-username show \
      --resource-group "$ACS_RESOURCE_GROUP" \
      --email-service-name "$ACS_EMAIL_SERVICE" \
      --domain-name "$MAIL_DOMAIN" \
      --sender-username "$local_part" \
      >/dev/null 2>&1; then
    log "Updating ACS sender username: ${address}"
    az communication email domain sender-username create \
      --resource-group "$ACS_RESOURCE_GROUP" \
      --email-service-name "$ACS_EMAIL_SERVICE" \
      --domain-name "$MAIL_DOMAIN" \
      --sender-username "$local_part" \
      --username "$local_part" \
      --display-name "$display_name" \
      >/dev/null
    updated_senders=$((updated_senders + 1))
  else
    log "Creating ACS sender username: ${address}"
    az communication email domain sender-username create \
      --resource-group "$ACS_RESOURCE_GROUP" \
      --email-service-name "$ACS_EMAIL_SERVICE" \
      --domain-name "$MAIL_DOMAIN" \
      --sender-username "$local_part" \
      --username "$local_part" \
      --display-name "$display_name" \
      >/dev/null
    created_senders=$((created_senders + 1))
  fi
done

log "Verifying Mailcow aliases"
mailcow_api GET "/api/v1/get/alias/all" |
  jq -r '
    .[]
    | select(.address == "info@photonfiber.pk"
          or .address == "support@photonfiber.pk"
          or .address == "billing@photonfiber.pk"
          or .address == "noreply@photonfiber.pk"
          or .address == "dmarc@photonfiber.pk")
    | [.address, .goto, (.active | tostring)]
    | @tsv
  ' |
  awk 'BEGIN { printf "%-32s %-32s %s\n", "ADDRESS", "DELIVERS TO", "ACTIVE" }
       { printf "%-32s %-32s %s\n", $1, $2, $3 }'

log "Verifying ACS sender usernames"
az communication email domain sender-username list \
  --resource-group "$ACS_RESOURCE_GROUP" \
  --email-service-name "$ACS_EMAIL_SERVICE" \
  --domain-name "$MAIL_DOMAIN" \
  --query "[?contains(['info','support','billing','noreply','dmarc'], username)].{Username:username,DisplayName:displayName}" \
  --output table

cat <<EOF

[PFIF Addresses] Complete.

Mailcow aliases created:       ${created_aliases}
Mailcow aliases already there: ${skipped_aliases}
ACS senders created:           ${created_senders}
ACS senders updated:           ${updated_senders}

All five addresses deliver to:
  ${TARGET_MAILBOX}

New ACS sender usernames can take several minutes to become active.
EOF
