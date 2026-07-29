variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "project_name" {
  type    = string
  default = "pfif"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "location" {
  type    = string
  default = "uaenorth"
}

variable "mail_hostname" {
  description = "Mailcow FQDN, such as mail.example.com."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", var.mail_hostname))
    error_message = "mail_hostname must be a valid lowercase FQDN."
  }
}

variable "mail_domain" {
  description = "Primary email domain."
  type        = string
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}

variable "admin_ssh_public_key_path" {
  type = string
}

variable "ssh_allowed_cidrs" {
  description = "Trusted source CIDRs allowed to connect to SSH."
  type        = list(string)
  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "ssh_allowed_cidrs must contain at least one valid IPv4 or IPv6 CIDR."
  }
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s_v2"
}

variable "os_disk_size_gb" {
  type    = number
  default = 64
}

variable "data_disk_size_gb" {
  type    = number
  default = 128
}

variable "os_disk_type" {
  type    = string
  default = "StandardSSD_LRS"
}

variable "data_disk_type" {
  type    = string
  default = "StandardSSD_LRS"
}

variable "private_ip_address" {
  type    = string
  default = "10.40.1.10"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.40.0.0/16"]
}

variable "subnet_address_prefixes" {
  type    = list(string)
  default = ["10.40.1.0/24"]
}

variable "availability_zone" {
  description = "Optional availability zone. Null creates non-zonal resources."
  type        = string
  default     = null
  nullable    = true
}

variable "accelerated_networking_enabled" {
  type    = bool
  default = false
}

variable "encryption_at_host_enabled" {
  type    = bool
  default = false
}

variable "create_backup_storage" {
  type    = bool
  default = true
}

variable "backup_replication_type" {
  type    = string
  default = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.backup_replication_type)
    error_message = "Unsupported Azure Storage replication type."
  }
}

variable "backup_retention_days" {
  description = "Days to retain local backups and active Azure backup blobs."
  type        = number
  default     = 14
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 1 and 365."
  }
}

variable "manage_cloudflare_dns" {
  type    = bool
  default = false
}

variable "cloudflare_zone_id" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
}

variable "tags" {
  type = map(string)
  default = {
    workload   = "mailcow"
    managed_by = "opentofu"
    project    = "pfif"
  }
}
