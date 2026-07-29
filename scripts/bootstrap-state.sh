#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

require_cmd az
az account set --subscription "$PFIF_AZURE_SUBSCRIPTION_ID"

info "Ensuring remote-state resource group"
az group create \
  --name "$PFIF_STATE_RESOURCE_GROUP" \
  --location "$PFIF_AZURE_LOCATION" \
  --output none

if ! az storage account show --resource-group "$PFIF_STATE_RESOURCE_GROUP" --name "$PFIF_STATE_STORAGE_ACCOUNT" >/dev/null 2>&1; then
  info "Creating remote-state storage account"
  az storage account create \
    --name "$PFIF_STATE_STORAGE_ACCOUNT" \
    --resource-group "$PFIF_STATE_RESOURCE_GROUP" \
    --location "$PFIF_AZURE_LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --output none
fi

storage_id="$(az storage account show --resource-group "$PFIF_STATE_RESOURCE_GROUP" --name "$PFIF_STATE_STORAGE_ACCOUNT" --query id -o tsv)"
principal_id="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -n "$principal_id" ]]; then
  role_count="$(az role assignment list --assignee-object-id "$principal_id" --scope "$storage_id" --query "[?roleDefinitionName=='Storage Blob Data Contributor'] | length(@)" -o tsv 2>/dev/null || echo 0)"
  if [[ ! "$role_count" =~ ^[1-9][0-9]*$ ]]; then
    info "Granting your Azure identity access to remote state blobs"
    az role assignment create \
      --assignee-object-id "$principal_id" \
      --assignee-principal-type User \
      --role "Storage Blob Data Contributor" \
      --scope "$storage_id" \
      --output none
    sleep 15
  fi
else
  warn "Could not resolve signed-in user object ID; assuming state blob RBAC already exists"
fi

info "Ensuring remote-state blob container"
for attempt in $(seq 1 12); do
  if az storage container create \
      --name "$PFIF_STATE_CONTAINER" \
      --account-name "$PFIF_STATE_STORAGE_ACCOUNT" \
      --auth-mode login \
      --output none 2>/dev/null; then
    break
  fi
  [[ "$attempt" -lt 12 ]] || die "Unable to create/access remote-state container after RBAC propagation wait"
  sleep 10
done

info "Remote state is ready"
