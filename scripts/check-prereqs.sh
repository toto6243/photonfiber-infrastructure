#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env
for cmd in az tofu ansible-playbook ansible-galaxy git python3 jq curl ssh scp rsync; do
  require_cmd "$cmd"
done

info "Checking Azure login"
az account show >/dev/null 2>&1 || die "Azure CLI is not logged in. Run: az login --tenant $PFIF_AZURE_TENANT_ID"
az account set --subscription "$PFIF_AZURE_SUBSCRIPTION_ID"
current_sub="$(az account show --query id -o tsv)"
[[ "$current_sub" == "$PFIF_AZURE_SUBSCRIPTION_ID" ]] || die "Azure subscription selection failed"

pub_key="$(expand_path "$PFIF_SSH_PUBLIC_KEY_PATH")"
priv_key="$(expand_path "$PFIF_SSH_PRIVATE_KEY_PATH")"
[[ -f "$pub_key" ]] || die "SSH public key not found: $pub_key"
[[ -f "$priv_key" ]] || die "SSH private key not found: $priv_key"

if truthy "${PFIF_MANAGE_CLOUDFLARE_DNS:-false}"; then
  resolve_cloudflare_zone_id
fi

info "Prerequisites are ready"
info "OpenTofu: $(tofu version | head -1)"
info "Ansible: $(ansible-playbook --version | head -1)"
info "Azure subscription: $current_sub"
