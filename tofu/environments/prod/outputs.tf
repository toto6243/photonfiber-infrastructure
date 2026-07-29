output "resource_group_name" {
  value = module.resource_group.name
}

output "vm_name" {
  value = local.names.vm
}

output "public_ip_name" {
  value = module.network.public_ip_name
}

output "admin_username" {
  value = var.admin_username
}

output "public_ip_address" {
  value = module.network.public_ip_address
}

output "private_ip_address" {
  value = module.network.private_ip_address
}

output "mail_hostname" {
  value = var.mail_hostname
}

output "mail_domain" {
  value = var.mail_domain
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${module.network.public_ip_address}"
}

output "backup_storage_account_name" {
  value = module.storage.storage_account_name
}

output "backup_container_name" {
  value = module.storage.container_name
}

output "backup_storage_enabled" {
  value = var.create_backup_storage
}

output "cloudflare_dns_managed" {
  value = var.manage_cloudflare_dns
}

output "dns_records" {
  value = {
    a = {
      name  = var.mail_hostname
      type  = "A"
      value = module.network.public_ip_address
      proxy = "DNS only"
    }
    mx = {
      name     = var.mail_domain
      type     = "MX"
      priority = 10
      value    = var.mail_hostname
    }
    spf = {
      name  = var.mail_domain
      type  = "TXT"
      value = "v=spf1 include:spf.protection.outlook.com -all"
    }
    dmarc = {
      name  = "_dmarc.${var.mail_domain}"
      type  = "TXT"
      value = "v=DMARC1; p=quarantine; rua=mailto:dmarc@${var.mail_domain}; adkim=s; aspf=s"
    }
    autoconfig = {
      name  = "autoconfig.${var.mail_domain}"
      type  = "CNAME"
      value = var.mail_hostname
      proxy = "DNS only"
    }
    autodiscover = {
      name  = "autodiscover.${var.mail_domain}"
      type  = "CNAME"
      value = var.mail_hostname
      proxy = "DNS only"
    }
  }
}

output "backup_retention_days" {
  value = var.backup_retention_days
}
