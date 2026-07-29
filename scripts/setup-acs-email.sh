#!/usr/bin/env bash
set -euo pipefail

# PFIF Azure Communication Services Email bootstrap
# Run from the PFIF project root: ./scripts/setup-acs-email.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

log() { printf '\n[ACS] %s\n' "$*"; }
die() { printf '\n[ACS] ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

need az
need curl
need jq
need python3

[[ -f "$ENV_FILE" ]] || die "Missing ${ENV_FILE}. Copy .env.example to .env first."

# Load PFIF settings without printing secrets.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

SUBSCRIPTION_ID="${PFIF_AZURE_SUBSCRIPTION_ID:-}"
TENANT_ID="${PFIF_AZURE_TENANT_ID:-}"
DOMAIN="${PFIF_MAIL_DOMAIN:-photonfiber.pk}"
CF_TOKEN="${PFIF_CLOUDFLARE_API_TOKEN:-}"
CF_ZONE_ID="${PFIF_CLOUDFLARE_ZONE_ID:-AUTO}"

RESOURCE_GROUP="${PFIF_ACS_RESOURCE_GROUP:-pfif-email-rg}"
ACS_NAME="${PFIF_ACS_NAME:-photonfiber-acs}"
EMAIL_SERVICE_NAME="${PFIF_ACS_EMAIL_SERVICE_NAME:-photonfiber-email-service}"
DATA_LOCATION="${PFIF_ACS_DATA_LOCATION:-europe}"
ENTRA_APP_NAME="${PFIF_ACS_ENTRA_APP_NAME:-pfif-mailcow-smtp}"
SMTP_RESOURCE_NAME="${PFIF_ACS_SMTP_RESOURCE_NAME:-pfif-mailcow-smtp}"
SMTP_USERNAME="${PFIF_ACS_SMTP_USERNAME:-pfif-mailcow}"
SENDER_USERNAME="${PFIF_ACS_SENDER_USERNAME:-noreply}"
SENDER_DISPLAY_NAME="${PFIF_ACS_SENDER_DISPLAY_NAME:-Photon Fiber Networks}"

[[ -n "$SUBSCRIPTION_ID" ]] || die "PFIF_AZURE_SUBSCRIPTION_ID is missing in .env"
[[ -n "$TENANT_ID" ]] || die "PFIF_AZURE_TENANT_ID is missing in .env"
[[ -n "$CF_TOKEN" ]] || die "PFIF_CLOUDFLARE_API_TOKEN is missing in .env"

log "Checking Azure login and selecting subscription"
az account show >/dev/null 2>&1 || die "Azure CLI is not logged in. Run: az login"
az account set --subscription "$SUBSCRIPTION_ID"

CURRENT_TENANT="$(az account show --query tenantId -o tsv)"
[[ "$CURRENT_TENANT" == "$TENANT_ID" ]] || die "Azure CLI tenant ${CURRENT_TENANT} does not match PFIF_AZURE_TENANT_ID ${TENANT_ID}"

log "Installing/updating Azure Communication CLI extension"
az extension add --name communication --upgrade --yes >/dev/null

log "Registering Microsoft.Communication provider"
az provider register --namespace Microsoft.Communication --wait >/dev/null

log "Resolving Cloudflare zone"
if [[ -z "$CF_ZONE_ID" || "$CF_ZONE_ID" == "AUTO" ]]; then
  CF_ZONE_ID="$(
    curl -fsS "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" |
    jq -r 'if .success and (.result|length)==1 then .result[0].id else empty end'
  )"
fi
[[ -n "$CF_ZONE_ID" && "$CF_ZONE_ID" != "null" ]] || die "Could not resolve Cloudflare zone ID for ${DOMAIN}"

cf_api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json"
  fi
}

cf_upsert_exact() {
  local type="$1" name="$2" content="$3"
  local proxied="${4:-false}" ttl="${5:-300}"
  local existing id payload result

  existing="$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}&per_page=100")"
  id="$(jq -r --arg content "$content" '.result[]? | select(.content==$content) | .id' <<<"$existing" | head -n1)"

  payload="$(jq -nc \
    --arg type "$type" --arg name "$name" --arg content "$content" \
    --argjson ttl "$ttl" --argjson proxied "$proxied" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied,comment:"Managed by PFIF ACS bootstrap"}')"

  if [[ -n "$id" ]]; then
    result="$(cf_api PUT "/zones/${CF_ZONE_ID}/dns_records/${id}" "$payload")"
  else
    result="$(cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$payload")"
  fi
  jq -e '.success == true' >/dev/null <<<"$result" || {
    jq . <<<"$result" >&2
    die "Cloudflare failed to upsert ${type} ${name}"
  }
}

cf_upsert_spf() {
  local name="$1" content="$2"
  local existing id payload result

  existing="$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?type=TXT&name=${name}&per_page=100")"
  id="$(jq -r '.result[]? | select(.content | startswith("v=spf1")) | .id' <<<"$existing" | head -n1)"
  payload="$(jq -nc --arg name "$name" --arg content "$content" \
    '{type:"TXT",name:$name,content:$content,ttl:300,proxied:false,comment:"Managed by PFIF ACS bootstrap"}')"

  if [[ -n "$id" ]]; then
    result="$(cf_api PUT "/zones/${CF_ZONE_ID}/dns_records/${id}" "$payload")"
  else
    result="$(cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$payload")"
  fi
  jq -e '.success == true' >/dev/null <<<"$result" || {
    jq . <<<"$result" >&2
    die "Cloudflare failed to upsert SPF for ${name}"
  }
}

log "Creating resource group"
az group create \
  --name "$RESOURCE_GROUP" \
  --location uaenorth \
  --tags project=pfif workload=mailcow environment=prod managed_by=script domain="$DOMAIN" \
  >/dev/null

log "Creating Azure Communication Services resource"
if ! az communication show -g "$RESOURCE_GROUP" -n "$ACS_NAME" >/dev/null 2>&1; then
  az communication create \
    --name "$ACS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location global \
    --data-location "$DATA_LOCATION" \
    --tags project=pfif workload=mailcow environment=prod managed_by=script domain="$DOMAIN" \
    >/dev/null
fi

log "Creating Email Communication Service"
if ! az communication email show -g "$RESOURCE_GROUP" -n "$EMAIL_SERVICE_NAME" >/dev/null 2>&1; then
  az communication email create \
    --name "$EMAIL_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location global \
    --data-location "$DATA_LOCATION" \
    --tags project=pfif workload=mailcow environment=prod managed_by=script domain="$DOMAIN" \
    >/dev/null
fi

log "Creating customer-managed email domain ${DOMAIN}"
if ! az communication email domain show \
    -g "$RESOURCE_GROUP" \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --name "$DOMAIN" >/dev/null 2>&1; then
  az communication email domain create \
    --name "$DOMAIN" \
    --resource-group "$RESOURCE_GROUP" \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --location global \
    --domain-management CustomerManaged \
    --user-engmnt-tracking Disabled \
    >/dev/null
fi

DOMAIN_JSON="$(
  az communication email domain show \
    -g "$RESOURCE_GROUP" \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --name "$DOMAIN" -o json
)"

DOMAIN_TXT="$(jq -r '.verificationRecords.Domain.value // empty' <<<"$DOMAIN_JSON")"
SPF_TXT="$(jq -r '.verificationRecords.SPF.value // empty' <<<"$DOMAIN_JSON")"
DKIM_NAME="$(jq -r '.verificationRecords.DKIM.name // empty' <<<"$DOMAIN_JSON")"
DKIM_VALUE="$(jq -r '.verificationRecords.DKIM.value // empty' <<<"$DOMAIN_JSON")"
DKIM2_NAME="$(jq -r '.verificationRecords.DKIM2.name // empty' <<<"$DOMAIN_JSON")"
DKIM2_VALUE="$(jq -r '.verificationRecords.DKIM2.value // empty' <<<"$DOMAIN_JSON")"
DOMAIN_ID="$(jq -r '.id' <<<"$DOMAIN_JSON")"

[[ -n "$DOMAIN_TXT" && -n "$SPF_TXT" && -n "$DKIM_NAME" && -n "$DKIM_VALUE" && -n "$DKIM2_NAME" && -n "$DKIM2_VALUE" ]] \
  || die "Azure did not return all required domain-verification records"

log "Publishing Azure verification, SPF, and DKIM records in Cloudflare"
cf_upsert_exact TXT "$DOMAIN" "$DOMAIN_TXT"
cf_upsert_spf "$DOMAIN" "$SPF_TXT"
cf_upsert_exact CNAME "${DKIM_NAME}.${DOMAIN}" "$DKIM_VALUE"
cf_upsert_exact CNAME "${DKIM2_NAME}.${DOMAIN}" "$DKIM2_VALUE"

log "Initiating Azure verification"
for verification_type in Domain SPF DKIM DKIM2; do
  az communication email domain initiate-verification \
    --domain-name "$DOMAIN" \
    --email-service-name "$EMAIL_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --verification-type "$verification_type" \
    >/dev/null 2>&1 || true
done

log "Waiting up to 15 minutes for DNS verification"
verified=false
for attempt in $(seq 1 30); do
  DOMAIN_JSON="$(
    az communication email domain show \
      -g "$RESOURCE_GROUP" \
      --email-service-name "$EMAIL_SERVICE_NAME" \
      --name "$DOMAIN" -o json
  )"

  DOMAIN_STATE="$(jq -r '.verificationStates.Domain.status // "Unknown"' <<<"$DOMAIN_JSON")"
  SPF_STATE="$(jq -r '.verificationStates.SPF.status // "Unknown"' <<<"$DOMAIN_JSON")"
  DKIM_STATE="$(jq -r '.verificationStates.DKIM.status // "Unknown"' <<<"$DOMAIN_JSON")"
  DKIM2_STATE="$(jq -r '.verificationStates.DKIM2.status // "Unknown"' <<<"$DOMAIN_JSON")"

  printf '[ACS] Domain=%s SPF=%s DKIM=%s DKIM2=%s\n' \
    "$DOMAIN_STATE" "$SPF_STATE" "$DKIM_STATE" "$DKIM2_STATE"

  if [[ "$DOMAIN_STATE" == "Verified" && "$SPF_STATE" == "Verified" &&
        "$DKIM_STATE" == "Verified" && "$DKIM2_STATE" == "Verified" ]]; then
    verified=true
    break
  fi
  sleep 30
done

if [[ "$verified" != true ]]; then
  cat >&2 <<EOF

[ACS] DNS records were created, but Azure verification is not complete yet.
[ACS] Wait a few minutes and rerun this same script. It is idempotent.
EOF
  exit 2
fi

log "Linking verified domain to Azure Communication Services"
az communication update \
  --name "$ACS_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --linked-domains "$DOMAIN_ID" \
  >/dev/null

log "Creating/updating Entra application for SMTP authentication"
APP_ID="$(az ad app list --display-name "$ENTRA_APP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$ENTRA_APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)"
fi

SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)"
if [[ -z "$SP_OBJECT_ID" ]]; then
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
fi

ACS_ID="$(az communication show -g "$RESOURCE_GROUP" -n "$ACS_NAME" --query id -o tsv)"

log "Assigning Communication and Email Service Owner role"
if ! az role assignment list \
    --assignee-object-id "$SP_OBJECT_ID" \
    --scope "$ACS_ID" \
    --role "Communication and Email Service Owner" \
    --query '[0].id' -o tsv | grep -q .; then
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Communication and Email Service Owner" \
    --scope "$ACS_ID" \
    >/dev/null
fi

log "Creating SMTP username resource"
# RBAC propagation can take a short time.
for attempt in $(seq 1 12); do
  if az communication smtp-username create \
      --resource-group "$RESOURCE_GROUP" \
      --comm-service-name "$ACS_NAME" \
      --smtp-username "$SMTP_RESOURCE_NAME" \
      --username "$SMTP_USERNAME" \
      --entra-application-id "$APP_ID" \
      --tenant-id "$TENANT_ID" \
      >/dev/null 2>&1; then
    break
  fi
  [[ "$attempt" -eq 12 ]] && die "Could not create SMTP username after waiting for RBAC propagation"
  sleep 15
done

log "Creating MailFrom sender username ${SENDER_USERNAME}@${DOMAIN}"
az communication email domain sender-username create \
  --resource-group "$RESOURCE_GROUP" \
  --email-service-name "$EMAIL_SERVICE_NAME" \
  --domain-name "$DOMAIN" \
  --sender-username "$SENDER_USERNAME" \
  --username "$SENDER_USERNAME" \
  --display-name "$SENDER_DISPLAY_NAME" \
  >/dev/null 2>&1 || true

EXISTING_RELAY_PASSWORD="${PFIF_SMTP_RELAY_PASSWORD:-}"
EXISTING_RELAY_USERNAME="${PFIF_SMTP_RELAY_USERNAME:-}"

if [[ -n "$EXISTING_RELAY_PASSWORD" && "$EXISTING_RELAY_USERNAME" == "$SMTP_USERNAME" ]]; then
  SMTP_PASSWORD="$EXISTING_RELAY_PASSWORD"
  log "Reusing SMTP secret already stored in .env"
else
  log "Generating a new Entra client secret for SMTP"
  SMTP_PASSWORD="$(
    az ad app credential reset \
      --id "$APP_ID" \
      --append \
      --display-name "PFIF Mailcow SMTP" \
      --years 1 \
      --query password -o tsv
  )"
fi

log "Writing SMTP relay settings to .env"
python3 - "$ENV_FILE" "$SMTP_USERNAME" "$SMTP_PASSWORD" "$RESOURCE_GROUP" "$ACS_NAME" "$EMAIL_SERVICE_NAME" "$APP_ID" <<'PY'
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
values = {
    "PFIF_SMTP_RELAY_ENABLED": "true",
    "PFIF_SMTP_RELAY_HOST": "smtp.azurecomm.net",
    "PFIF_SMTP_RELAY_PORT": "587",
    "PFIF_SMTP_RELAY_USERNAME": sys.argv[2],
    "PFIF_SMTP_RELAY_PASSWORD": sys.argv[3],
    "PFIF_SMTP_RELAY_TLS_MODE": "starttls",
    "PFIF_ACS_RESOURCE_GROUP": sys.argv[4],
    "PFIF_ACS_NAME": sys.argv[5],
    "PFIF_ACS_EMAIL_SERVICE_NAME": sys.argv[6],
    "PFIF_ACS_ENTRA_APP_ID": sys.argv[7],
}

lines = env_path.read_text().splitlines()
seen = set()
out = []

def quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"

for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue
    key = line.split("=", 1)[0].strip()
    if key in values:
        out.append(f"{key}={quote(values[key])}")
        seen.add(key)
    else:
        out.append(line)

if out and out[-1] != "":
    out.append("")
out.append("# Azure Communication Services Email SMTP relay")
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={quote(value)}")

env_path.write_text("\n".join(out) + "\n")
PY

chmod 600 "$ENV_FILE"

cat <<EOF

[ACS] Setup complete.

SMTP host:      smtp.azurecomm.net
SMTP port:      587
SMTP username:  ${SMTP_USERNAME}
TLS mode:       starttls
Sender created: ${SENDER_USERNAME}@${DOMAIN}

The SMTP password was written directly to:
  ${ENV_FILE}

Next:
  ./pfif check
  ./pfif plan

Do not paste or commit your .env file.
EOF
