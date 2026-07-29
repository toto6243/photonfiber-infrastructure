variable "name" { type = string }
variable "computer_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_ssh_public_key" { type = string }
variable "network_interface_id" { type = string }
variable "availability_zone" {
  type     = string
  default  = null
  nullable = true
}
variable "os_disk_size_gb" { type = number }
variable "data_disk_size_gb" { type = number }
variable "os_disk_type" { type = string }
variable "data_disk_type" { type = string }
variable "encryption_at_host_enabled" {
  type    = bool
  default = false
}
variable "cloud_init" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
