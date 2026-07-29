resource "azurerm_storage_account" "backup" {
  count = var.create_backup_storage ? 1 : 0

  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  cross_tenant_replication_enabled = false
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.delete_retention_days
    }
    container_delete_retention_policy {
      days = var.delete_retention_days
    }
  }
}

resource "azurerm_storage_container" "backup" {
  count = var.create_backup_storage ? 1 : 0

  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.backup[0].id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "backup_retention" {
  count = var.create_backup_storage ? 1 : 0

  storage_account_id = azurerm_storage_account.backup[0].id

  rule {
    name    = "deleteExpiredMailcowBackups"
    enabled = true

    filters {
      prefix_match = ["${var.container_name}/mailcow-"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.delete_retention_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = var.delete_retention_days
      }

      version {
        delete_after_days_since_creation = var.delete_retention_days
      }
    }
  }

  depends_on = [azurerm_storage_container.backup]
}
