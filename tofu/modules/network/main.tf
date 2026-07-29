resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.subnet_address_prefixes
}

resource "azurerm_public_ip" "this" {
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  domain_name_label   = var.domain_name_label
  zones               = var.availability_zone == null ? null : [var.availability_zone]
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                          = var.nic_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  accelerated_networking_enabled = var.accelerated_networking_enabled
  tags                          = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address
    public_ip_address_id          = azurerm_public_ip.this.id
    primary                       = true
  }
}
