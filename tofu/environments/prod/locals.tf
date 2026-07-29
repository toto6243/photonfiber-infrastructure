locals {
  prefix = lower("${var.project_name}-${var.environment}")

  names = {
    resource_group = "${local.prefix}-rg"
    vnet           = "${local.prefix}-vnet"
    subnet         = "${local.prefix}-mail-subnet"
    public_ip      = "${local.prefix}-pip"
    nic            = "${local.prefix}-nic"
    nsg            = "${local.prefix}-nsg"
    vm             = "${local.prefix}-mail"
  }

  common_tags = merge(var.tags, {
    environment = var.environment
    domain      = var.mail_domain
  })

  ssh_public_key = trimspace(file(pathexpand(var.admin_ssh_public_key_path)))
}
