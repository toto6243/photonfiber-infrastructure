variable "create_backup_storage" {
  type    = bool
  default = true
}
variable "storage_account_name" { type = string }
variable "container_name" {
  type    = string
  default = "mailcow-backups"
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "replication_type" {
  type    = string
  default = "LRS"
}
variable "delete_retention_days" {
  description = "Days to retain active backup blobs before lifecycle deletion and soft-deleted blobs after deletion."
  type        = number
  default     = 14
  validation {
    condition     = var.delete_retention_days >= 1 && var.delete_retention_days <= 365
    error_message = "delete_retention_days must be between 1 and 365."
  }
}
variable "public_network_access_enabled" {
  type    = bool
  default = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
