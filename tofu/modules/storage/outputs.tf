output "storage_account_id" { value = try(azurerm_storage_account.backup[0].id, null) }
output "storage_account_name" { value = try(azurerm_storage_account.backup[0].name, null) }
output "container_name" { value = try(azurerm_storage_container.backup[0].name, null) }
output "primary_blob_endpoint" { value = try(azurerm_storage_account.backup[0].primary_blob_endpoint, null) }
