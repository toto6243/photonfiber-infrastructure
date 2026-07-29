resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  special = false
}

module "resource_group" {
  source = "../../modules/resource-group"

  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source = "../../modules/network"

  resource_group_name             = module.resource_group.name
  location                        = module.resource_group.location
  vnet_name                       = local.names.vnet
  vnet_address_space              = var.vnet_address_space
  subnet_name                     = local.names.subnet
  subnet_address_prefixes         = var.subnet_address_prefixes
  public_ip_name                  = local.names.public_ip
  nic_name                        = local.names.nic
  private_ip_address              = var.private_ip_address
  domain_name_label               = replace("${local.prefix}-mail", "_", "-")
  availability_zone              = var.availability_zone
  accelerated_networking_enabled = var.accelerated_networking_enabled
  tags                            = local.common_tags
}

module "nsg" {
  source = "../../modules/nsg"

  name                 = local.names.nsg
  resource_group_name  = module.resource_group.name
  location             = module.resource_group.location
  network_interface_id = module.network.nic_id
  ssh_allowed_cidrs    = var.ssh_allowed_cidrs
  tags                  = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  create_backup_storage         = var.create_backup_storage
  storage_account_name          = substr(replace("${var.project_name}${var.environment}${random_string.storage_suffix.result}", "-", ""), 0, 24)
  container_name                = "mailcow-backups"
  resource_group_name           = module.resource_group.name
  location                      = module.resource_group.location
  replication_type              = var.backup_replication_type
  delete_retention_days         = var.backup_retention_days
  public_network_access_enabled = true
  tags                          = local.common_tags
}

module "vm" {
  source = "../../modules/vm"

  name                       = local.names.vm
  computer_name              = "mailcow"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  vm_size                    = var.vm_size
  admin_username             = var.admin_username
  admin_ssh_public_key       = local.ssh_public_key
  network_interface_id       = module.network.nic_id
  availability_zone          = var.availability_zone
  os_disk_size_gb            = var.os_disk_size_gb
  data_disk_size_gb          = var.data_disk_size_gb
  os_disk_type               = var.os_disk_type
  data_disk_type             = var.data_disk_type
  encryption_at_host_enabled = var.encryption_at_host_enabled
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname = "mailcow"
  })
  tags = local.common_tags

  depends_on = [module.nsg]
}

resource "azurerm_role_assignment" "mailcow_backup_blob" {
  count = var.create_backup_storage ? 1 : 0

  scope                            = module.storage.storage_account_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = module.vm.principal_id
  skip_service_principal_aad_check = true
}

resource "cloudflare_dns_record" "mail_a" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.mail_hostname
  type    = "A"
  content = module.network.public_ip_address
  ttl     = 300
  proxied = false
  comment = "Managed by PFIF/OpenTofu"
}

resource "cloudflare_dns_record" "mail_mx" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id  = var.cloudflare_zone_id
  name     = var.mail_domain
  type     = "MX"
  content  = var.mail_hostname
  priority = 10
  ttl      = 300
  comment  = "Managed by PFIF/OpenTofu"
}

resource "cloudflare_dns_record" "spf" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.mail_domain
  type    = "TXT"
  content = "v=spf1 include:spf.protection.outlook.com -all"
  ttl     = 300
  comment = "Managed by PFIF/OpenTofu"
}

resource "cloudflare_dns_record" "dmarc" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "_dmarc.${var.mail_domain}"
  type    = "TXT"
  content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@${var.mail_domain}; adkim=s; aspf=s"
  ttl     = 300
  comment = "Managed by PFIF/OpenTofu"
}

resource "cloudflare_dns_record" "autoconfig" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "autoconfig.${var.mail_domain}"
  type    = "CNAME"
  content = var.mail_hostname
  ttl     = 300
  proxied = false
  comment = "Managed by PFIF/OpenTofu"
}

resource "cloudflare_dns_record" "autodiscover" {
  count = var.manage_cloudflare_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "autodiscover.${var.mail_domain}"
  type    = "CNAME"
  content = var.mail_hostname
  ttl     = 300
  proxied = false
  comment = "Managed by PFIF/OpenTofu"
}
