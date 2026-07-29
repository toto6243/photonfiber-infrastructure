variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "vnet_name" { type = string }
variable "vnet_address_space" { type = list(string) }
variable "subnet_name" { type = string }
variable "subnet_address_prefixes" { type = list(string) }
variable "public_ip_name" { type = string }
variable "nic_name" { type = string }
variable "private_ip_address" { type = string }
variable "domain_name_label" { type = string }
variable "availability_zone" {
  type     = string
  default  = null
  nullable = true
}
variable "accelerated_networking_enabled" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
