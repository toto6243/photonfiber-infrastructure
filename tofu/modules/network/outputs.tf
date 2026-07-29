output "vnet_id" { value = azurerm_virtual_network.this.id }
output "subnet_id" { value = azurerm_subnet.this.id }
output "nic_id" { value = azurerm_network_interface.this.id }
output "public_ip_id" { value = azurerm_public_ip.this.id }
output "public_ip_name" { value = azurerm_public_ip.this.name }
output "public_ip_address" { value = azurerm_public_ip.this.ip_address }
output "public_ip_fqdn" { value = azurerm_public_ip.this.fqdn }
output "private_ip_address" { value = azurerm_network_interface.this.private_ip_address }
